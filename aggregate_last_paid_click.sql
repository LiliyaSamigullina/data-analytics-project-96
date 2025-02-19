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
),
tab AS (
    SELECT
        visitor_id,
        MAX(visit_date) AS last_visit
    FROM sessions
    WHERE medium != 'organic'
    GROUP BY 1
),
last_paid_click AS (
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
),
ag_lpc AS (
    SELECT
        lpc.visit_date::date,
        lpc.utm_source,
        lpc.utm_medium,
        lpc.utm_campaign,
        COUNT(DISTINCT lpc.visitor_id) AS visitors_count,
        COUNT(lpc.lead_id) AS leads_count,
        COUNT(lpc.lead_id) FILTER (
            WHERE lpc.closing_reason = 'Успешно реализовано' OR lpc.status_id = 142
        ) AS purchases_count,
        SUM(amount) AS revenue
    FROM last_paid_click AS lpc
    GROUP BY 1, 2, 3, 4
)
SELECT
    ag_lpc.visit_date,
    ag_lpc.visitors_count,
    ag_lpc.utm_source,
    ag_lpc.utm_medium,
    ag_lpc.utm_campaign,
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
LIMIT 15;
