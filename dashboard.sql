--distinct visitor count and lead count by date
SELECT
    s.visit_date::date AS visit_date,
    COUNT(DISTINCT s.visitor_id) AS distinct_visitors_count,
    COUNT(DISTINCT l.lead_id) AS leads_count
FROM sessions AS s
LEFT JOIN leads AS l
    ON s.visit_date::date = l.created_at::date
GROUP BY 1
ORDER BY 1;


-- visitors by source
SELECT
    source,
    COUNT(visitor_id) AS visitors_count
FROM sessions s
GROUP BY 1
ORDER BY 2 DESC;


-- distinct visitors by week
SELECT
    TO_CHAR(visit_date, 'W') AS week_of_month,
    COUNT(DISTINCT visitor_id) AS visitor_count
FROM sessions
GROUP BY 1
ORDER BY 1;


--LCR calculation
WITH tbl AS (
    SELECT
        s.visit_date::date AS visit_date,
        COUNT(DISTINCT s.visitor_id) AS distinct_visitors_count,
        COUNT(DISTINCT l.lead_id) AS leads_count
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON s.visit_date::date = l.created_at::date
    GROUP BY 1
    ORDER BY 1
)
SELECT
    SUM(leads_count)::NUMERIC / SUM(distinct_visitors_count)::NUMERIC * 100.0 AS lcr
FROM tbl;


--conversion rate calculation by source
WITH tbl AS (
    SELECT
        s.source,
        s.medium,
        s.campaign,
        COUNT(l.lead_id) AS leads_count,
        COUNT(l.lead_id) FILTER (WHERE l.closing_reason = 'Успешная продажа' OR l.status_id = 142) AS purchase_count
    FROM leads AS l
    LEFT JOIN sessions AS s
        ON l.visitor_id = s.visitor_id
    WHERE s.medium != 'organic'
    GROUP BY 1, 2, 3
)
SELECT
    source,
    medium,
    campaign,
    leads_count,
    purchase_count,
    ROUND(100.0 * purchase_count / leads_count, 2) AS cr
FROM tbl
ORDER BY 6 DESC;


--ROI calculation
WITH ads AS (
    SELECT
        campaign_date::date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM vk_ads
    GROUP BY 1, 2, 3, 4
    UNION
    SELECT
        campaign_date::date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY 1, 2, 3, 4
), tab AS (
    SELECT
        visitor_id,
        MAX(visit_date) AS last_visit
    FROM sessions
    WHERE medium != 'organic'
    GROUP BY 1
), last_paid_click AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM sessions AS s
    INNER JOIN tab
        ON s.visitor_id = tab.visitor_id AND s.visit_date = tab.last_visit
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id AND tab.last_visit <= l.created_at
), ag_lpc AS (
    SELECT
        lpc.visit_date::date,
        lpc.utm_source,
        lpc.utm_medium,
        lpc.utm_campaign,
        COUNT(lpc.visitor_id) AS visitors_count,
        COUNT(lpc.lead_id) AS leads_count,
        COUNT(lpc.lead_id) FILTER (
            WHERE lpc.closing_reason = 'Успешно реализовано' OR lpc.status_id = 142
        ) AS purchases_count,
        SUM(amount) AS revenue
    FROM last_paid_click AS lpc
    GROUP BY 1, 2, 3, 4
), tab2 AS (
    SELECT
        ag_lpc.visit_date,
        ag_lpc.utm_source,
        ag_lpc.utm_medium,
        ag_lpc.utm_campaign,
        ag_lpc.visitors_count,
        ads.total_cost,
        ag_lpc.leads_count,
        ag_lpc.purchases_count,
        ag_lpc.revenue
    FROM ag_lpc
    LEFT JOIN ads
        ON ag_lpc.utm_source = ads.utm_source
        AND ag_lpc.utm_medium = ads.utm_medium
        AND ag_lpc.utm_campaign = ads.utm_campaign
        AND ag_lpc.visit_date::date = ads.campaign_date
    ORDER BY
        revenue DESC NULLS LAST,
        visit_date ASC,
        visitors_count DESC,
        utm_source ASC,
        utm_medium ASC,
        utm_campaign ASC
)
SELECT
    utm_source,
    utm_medium,
    utm_campaign,
    CASE 
    	WHEN SUM(visitors_count) = 0 THEN 0
    	ELSE ROUND(SUM(total_cost) / SUM(visitors_count), 2)
    END AS cpu,
    CASE 
    	WHEN SUM(leads_count) = 0 THEN 0
    	ELSE ROUND(SUM(total_cost) / SUM(leads_count), 2)
    END AS cpl,
    CASE 
    	WHEN SUM(purchases_count) = 0 THEN 0
    	ELSE ROUND(SUM(total_cost) / SUM(purchases_count), 2)
    END AS cppu,
    ROUND(
        100.0 * (SUM(revenue) - SUM(total_cost)) / SUM(total_cost)
    , 2) AS roi
FROM tab2
WHERE utm_source IN ('vk', 'yandex')
GROUP BY 1, 2, 3
ORDER BY roi DESC NULLS LAST;


-- Total spent calculation
with tab as (
    select
        vk.campaign_date::date,
        vk.utm_source,
        vk.utm_medium,
        vk.utm_campaign,
        sum(vk.daily_spent) as daily_spent
    from vk_ads as vk
    group by
        1, 2, 3, 4
    union all
    select
        ya.campaign_date::date,
        ya.utm_source,
        ya.utm_medium,
        ya.utm_campaign,
        sum(ya.daily_spent) as daily_spent
    from ya_ads as ya
    group by
        1, 2, 3, 4
)
select
    tab.campaign_date::date,
    tab.utm_source,
    tab.utm_medium,
    tab.utm_campaign,
    tab.daily_spent
from tab
order by 1;


--visitor & campaigns count by dates
SELECT
    s.visit_date::date AS visit_date,
    COUNT(DISTINCT s.visitor_id) AS visitor_count,
    COUNT(DISTINCT s.campaign) AS campaign_count
FROM sessions AS s
WHERE s.source = 'vk' or s.source = 'ya'
GROUP BY 1
ORDER BY 1;


--90% leads close-out timeline
WITH tab AS (
    SELECT
        s.visitor_id,
        s.visit_date::date,
        l.lead_id,
        l.created_at::date,
        l.created_at::date - s.visit_date::date AS days_passed,
        ntile(10) OVER (
            ORDER BY l.created_at::date - s.visit_date::date
        ) AS ntile
    FROM sessions AS s
    INNER JOIN leads AS l
        ON s.visitor_id = l.visitor_id
    WHERE
        l.closing_reason = 'Успешная продажа'
        AND s.visit_date::date <= l.created_at::date
)
SELECT max(days_passed) AS days_passed
FROM tab
WHERE ntile = 9;
