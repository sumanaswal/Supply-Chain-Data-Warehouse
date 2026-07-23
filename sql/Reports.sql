WITH monthly_order_details AS (
	SELECT 
		DATE_TRUNC('month',d.full_date)::DATE	AS month,
		SUM(f.net_saleS)						AS total_revenue,
		SUM(f.order_quantity)					AS total_quantity,
		COUNT(DISTINCT customer_key)			AS unique_customers,
		sum(f.net_sales) / COUNT(DISTINCT order_id)	AS Avg_order_value
	FROM gold.fact_order_items f
	JOIN gold.dim_date d ON d.date_key = f.order_date_key
	JOIN gold.dim_product p	ON p.product_key = f.product_key
	GROUP BY 1
),
category_rank AS (
	SELECT
		DATE_TRUNC('month',d.full_date)::DATE	AS month,
		p.category_name,
		sum(f.net_sales) as category_revenue,
		ROW_NUMBER() OVER(partition by DATE_TRUNC('month',d.full_date)::DATE ORDER BY sum(f.net_sales) DESC) as category_rnk
	FROM gold.fact_order_items f
	JOIN gold.dim_product p ON f.product_key = p.product_key
	JOIN gold.dim_date d	ON d.date_key = f.order_date_key
	GROUP BY 1,2
)

SELECT
	md.month,
	md.total_revenue,
	md.total_quantity,
	md.unique_customers,
	ROUND(md.avg_order_value,2) 	AS avg_order_value,
	cr.category_name 				AS top_category,
	cr.category_revenue,
	ROUND(100.0 * cr.category_revenue / md.total_revenue,2) AS category_contribution_pct,
	ROUND((md.total_revenue - LAG(md.total_revenue,12) OVER(order by md.month))* 100
	/ NULLIF(LAG(md.total_revenue,12) OVER(order by md.month) ,0),2)		AS YoY_growth_pct
FROM monthly_order_details md
JOIN category_rank cr on md.month = cr.month AND category_rnk = 1
ORDER BY md.month desc
LIMIT 6;
