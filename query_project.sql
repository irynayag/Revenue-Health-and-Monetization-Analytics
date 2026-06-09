WITH dates AS (
    SELECT
        u.language,
        u.age,
        p.user_id,
        p.payment_date,
        DATE_TRUNC('month', p.payment_date::timestamp) AS payment_month,
        p.revenue_amount_usd
    FROM games_payments p
    LEFT JOIN games_paid_users u ON p.user_id = u.user_id
),

user_monthly_revenue AS (
    SELECT 
        user_id,
        payment_month,
        language,
        age,
        SUM(revenue_amount_usd) AS current_month_revenue,
        
        LAG(payment_month) OVER (
            PARTITION BY user_id 
            ORDER BY payment_month
        ) AS previous_payment_month,

        LEAD(payment_month) OVER (
            PARTITION BY user_id 
            ORDER BY payment_month
        ) AS next_payment_month,

        LAG(SUM(revenue_amount_usd)) OVER (
            PARTITION BY user_id 
            ORDER BY payment_month
        ) AS previous_month_revenue
        
    FROM dates
    WHERE payment_date IS NOT NULL
    GROUP BY user_id, payment_month, language, age
),

monthly_aggregates AS (
    SELECT
        payment_month,
        language,
        age,
        ROUND((SUM(current_month_revenue))::numeric, 2) AS total_revenue, 
        COUNT(DISTINCT user_id) AS paid_users_group,
        COUNT(DISTINCT CASE WHEN previous_payment_month IS NULL THEN user_id ELSE NULL END) AS new_paid_users,
        ROUND(SUM(CASE WHEN previous_payment_month IS NULL THEN current_month_revenue ELSE 0 END)::numeric, 2) AS new_mrr,
        COUNT(DISTINCT CASE WHEN next_payment_month IS NULL THEN user_id ELSE NULL END) AS churned_users,
        ROUND(SUM(CASE WHEN next_payment_month IS NULL THEN current_month_revenue ELSE 0 END)::numeric, 2) AS churned_revenue,
        ROUND(SUM(CASE WHEN previous_payment_month = payment_month - INTERVAL '1 month' THEN current_month_revenue 
                       WHEN previous_payment_month IS NULL THEN current_month_revenue 
                       ELSE 0 
                  END)::numeric, 2) AS mrr_group,
        ROUND(SUM(CASE WHEN previous_payment_month = payment_month - INTERVAL '1 month' 
                       AND current_month_revenue > previous_month_revenue  
                       THEN current_month_revenue - previous_month_revenue
                       ELSE 0 
                  END)::numeric, 2) AS expansion_mrr,
        ROUND(SUM(CASE WHEN previous_payment_month = payment_month - INTERVAL '1 month' 
                       AND current_month_revenue < previous_month_revenue   
                       THEN previous_month_revenue - current_month_revenue
                       ELSE 0 
                  END)::numeric, 2) AS contraction_mrr
    FROM user_monthly_revenue
    GROUP BY payment_month, language, age
)

SELECT
    COALESCE(m.language, 'Unknown') AS language,
    COALESCE(m.age::text, 'Unknown') AS age,
    TO_CHAR(m.payment_month, 'YYYY-MM') AS payment_month,    
    m.total_revenue,
    m.paid_users_group AS paid_users,
    ROUND((m.total_revenue / NULLIF(m.paid_users_group, 0))::numeric, 2) AS arppu,
    m.mrr_group AS mrr,
    m.new_paid_users,
    m.new_mrr,
    m.churned_users,
    m.churned_revenue,
    m.expansion_mrr,
    m.contraction_mrr
FROM monthly_aggregates m
ORDER BY m.payment_month, m.language, m.age;
