-- ==============================================================================
-- 1. BASELINE VALIDATION: Volume & Date Ranges
-- ==============================================================================
-- This query confirms our data volume and establishes the exact time horizon of the dataset.
SELECT
	COUNT(DISTINCT order_id) AS total_unique_orders,
	COUNT(order_item_id) AS total_line_items,
	MIN(order_date) as earliest_order_date,
	MAX(order_date) as latest_order_date,
	COUNT(DISTINCT customer_id) AS total_active_customers
FROM fact_orders;

-- ==============================================================================
-- 2. MACRO FINANCIALS: Revenue, Discount Impact, and Margin
-- ==============================================================================
-- Establishing the global financial baseline before slicing the data.
SELECT
	SUM(order_item_total) AS gross_revenue,
	SUM(order_item_quantity) AS total_items_sold,

	-- calculating total dollar amount lost to discounts
	SUM(order_item_total * order_item_discount_rate) AS total_discount_amount,

	-- calculating net revenue (gross revenue - discount)
	SUM(order_item_total - (order_item_total * order_item_discount_rate)) as net_revenue
FROM fact_orders;

-- ==============================================================================
-- 3. CATEGORY PROFILING: High-Level Product Performance
-- ==============================================================================
-- Joining the Fact table with the Product Dimension to see where the volume lies.
SELECT 
    p.category_name,
    COUNT(f.order_item_id) AS total_transactions,
    SUM(f.order_item_quantity) AS total_units_sold,
    SUM(f.order_item_total) AS gross_revenue
FROM fact_orders f
JOIN dim_products p ON f.product_card_id = p.product_card_id
GROUP BY p.category_name
ORDER BY gross_revenue DESC
LIMIT 10;

-- ==============================================================================
-- 1. OVERALL SLA PERFORMANCE (Window Function for Percentages)
-- ==============================================================================
-- Understanding the macro delivery breakdown across the entire business.
SELECT
	delivery_status,
	COUNT(order_item_id) AS total_deliveries,
	round((COUNT(order_item_id) * 100.0) / SUM(COUNT(order_item_id)) OVER(),2) AS percentage_of_total
FROM fact_orders
GROUP BY delivery_status
ORDER BY total_deliveries DESC;

-- ==============================================================================
-- 2. VENDOR RISK ANALYSIS: Late Delivery Rates by Shipping Mode
-- ==============================================================================
-- Identifying which specific shipping tier is failing the most often.
SELECT
	shipping_mode,
	COUNT(order_item_id) AS total_shipments,
	SUM(late_delivery_risk) AS total_late_shipments,

	-- Calculating the failure rate. We multiply by 100.0 to force decimal division.
	ROUND((SUM(late_delivery_risk) * 100.0) / COUNT(order_item_id),2) AS late_delivery_rate_percent
FROM fact_orders
GROUP BY shipping_mode
ORDER BY late_delivery_rate_percent DESC;

-- ==============================================================================
-- 3. REGIONAL BOTTLENECKS: Finding the problem areas
-- ==============================================================================
-- Joining with the Customer Dimension to find which specific geographical 
-- regions suffer from the highest late delivery rates.
SELECT
	c.customer_country,
	c.customer_state,
	COUNT(o.order_item_id) AS total_orders,
	SUM(o.late_delivery_risk) AS late_deliveries,

	-- Using NULLIF to prevent potential division-by-zero errors
	ROUND((SUM(o.late_delivery_risk) * 100.0) / NULLIF(COUNT(o.order_item_id),0),2) AS late_rate_percent
FROM fact_orders o
JOIN dim_customers c
	ON o.customer_id = c.customer_id
GROUP BY c.customer_country, c.customer_state

-- The HAVING clause filters out low-volume regions so we only focus on 
-- statistically significant bottlenecks (e.g., states with more than 100 orders).
HAVING COUNT(o.order_item_id) > 100
ORDER BY late_rate_percent DESC
LIMIT 10;

-- ==============================================================================
-- 1. PROFIT MARGIN & DISCOUNT IMPACT ANALYSIS (Using a CTE)
-- ==============================================================================
-- First, we create a temporary result set (CTE) to calculate the raw dollar amounts.
WITH CategoryFinancials AS (
	SELECT
		p.category_name,
		SUM(o.order_item_total) AS gross_revenue,
		COUNT(o.order_item_quantity) AS total_units,

		-- calculating the exact dollar amount lost to discount
		SUM(o.order_item_total * order_item_discount_rate) AS total_discount_given
	FROM fact_orders o
	JOIN dim_products p
		ON p.product_card_id = o.product_card_id
	GROUP BY p.category_name
)
-- Next, we query the CTE to calculate the final percentages and net revenue.
SELECT
	category_name,
	gross_revenue,
	total_units,
	total_discount_given,
	(gross_revenue - total_discount_given) AS net_revenue,

	-- margin percentage
	ROUND(((gross_revenue - total_discount_given) / gross_revenue ) * 100,2) AS net_margin_percentage
FROM CategoryFinancials
ORDER BY net_revenue DESC
LIMIT 10;

-- ==============================================================================
-- 2. DISCOUNT RELIANCE (Identifying potentially toxic customer segments)
-- ==============================================================================
-- The business needs to know if certain regions only buy when items are heavily discounted.
SELECT
	c.customer_country,
	c.customer_state,
	COUNT(o.order_item_id) AS total_transactions,
	ROUND(AVG(order_item_discount_rate) * 100,2) AS avg_discount_percent,
	MAX(order_item_discount_rate) * 100 AS max_discount_percent_given
FROM fact_orders o
JOIN dim_customers c
	ON o.customer_id = c.customer_id
GROUP BY c.customer_country, c.customer_state
HAVING COUNT(o.order_item_id) > 500
ORDER BY avg_discount_percent DESC;

-- ==============================================================================
-- 1. RFM SEGMENTATION MODEL
-- ==============================================================================
-- First CTE: Calculate the raw metrics for every customer
WITH CustomerBase AS (
	SELECT
		customer_id,
		
		-- Recency, Frequency, Monetory
		MAX(order_date) AS last_purchase_date,
		COUNT(DISTINCT order_id) AS total_orders,
		SUM(order_item_total) AS total_spent
	FROM fact_orders 
	GROUP BY customer_id
),

-- Second CTE: Convert the last purchase date into "Days Since Last Order"
-- We use a subquery to find the absolute latest date in the dataset as our "today"
RFM_Calculation AS (
	SELECT 
		customer_id,

		-- MAX(order_date) is used but in production use CURRENT_DATE
		EXTRACT(DAY FROM (SELECT MAX(order_date) FROM fact_orders) - last_purchase_date) AS recency_days,
		total_orders,
		total_spent
	FROM CustomerBase
),

-- Third CTE: Score customers from 1 to 4 using NTILE
-- 4 is the best possible score, 1 is the worst.
RFM_Scoring AS (
	SELECT
		customer_id,	
		recency_days,
		total_orders,
		total_spent,

		-- Recency: Lower days is better, ordering by DESC puts the highest days in bucket 1
		NTILE(4) OVER(ORDER BY recency_days DESC) AS r_score,

		-- Frequency and Monetary: Higher is better, ordering by ASC puts the highest number in bucket 5
		NTILE(4) OVER(ORDER BY total_orders ASC) AS f_score,
		NTILE(4) OVER(ORDER BY total_spent ASC) AS m_score
	FROM RFM_Calculation
)

-- Final Output: Combine the scores and assign readable business labels
SELECT
	customer_id,
	recency_days,
	total_orders,
	total_spent,

	-- concat a 3 digit RFM score string
	CONCAT(r_score, f_score, m_score) AS rfm_score,

	-- using CASE to group scores into meaningful marketing sagments
	CASE
		WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions (VIP)'
		WHEN r_score >= 3 AND f_score >= 3 THEN 'Recent Customers (Nurture)'
		WHEN r_score < 3 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk (High Value)'
		WHEN r_score < 2 AND f_score < 2 THEN 'Lost/Churned Customers'
		ELSE 'Average Core Customers'
	END AS customer_segment
FROM RFM_Scoring
ORDER BY rfm_score DESC;

















