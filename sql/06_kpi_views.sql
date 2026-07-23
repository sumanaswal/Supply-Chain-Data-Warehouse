--#########################################
-- Business KPI Logic - Core Metric Views
--#########################################

-- 1. Order & Delivery Performance

-- KPI 1.1 - On-Time Delivery Rate / Late Delivery Rate
-- Late Delivery Rate = (Number of Late Order Items / Total Order Itmes) x 100
-- On-Time Delivery Rate = 100 - Late Delivery Rate
CREATE VIEW gold.vw_delivery_performance AS
SELECT
	d.year,
	d.month_num,
	d.month_name,
	g.market,
	g.order_region,
	sm.shipping_mode,
	COUNT(*)											AS total_order_items,
	SUM(CASE WHEN f.is_late_delivery THEN 1 ELSE 0 END) AS total_late_orders,
	ROUND(100.0 * SUM(CASE WHEN f.is_late_delivery THEN 1 ELSE 0 END) 
		/ COUNT(*),2) 									AS late_delivery_rate_pct,
	ROUND(100.0 - (100.0 * SUM(CASE WHEN f.is_late_delivery THEN 1 ELSE 0 END) 
		/ COUNT(*)),2) 									AS on_time_delivery_rate,
	ROUND(AVG(f.shipping_delay_days),2) 					AS avg_shipping_delay_days
FROM gold.fact_order_items f
JOIN gold.dim_date d ON f.order_date_key = d.date_key
JOIN gold.dim_geography g ON f.geography_key = g.geography_key
JOIN gold.dim_shipping_mode sm ON f.shipping_mode_key = sm.shipping_mode_key
WHERE is_return_or_cancellation = FALSE
GROUP BY d.year,d.month_num,d.month_name,g.market,g.order_region,sm.shipping_mode;

-- KPI 1.2 - OTIF (On-Time-In-Full) Rate
-- OTIF = (Orders delivered On-TIme AND In-Full) / Total Orders X 100
-- "On-Time" = shipping_delay_days <= 0 (actual days <= scheduled days)
-- "In-Full" = orders was not a partial/cancelled/returned fulfillment
CREATE VIEW gold.vw_otif AS
WITH order_level AS (
	SELECT
		f.order_id,
		d.year,
		d.month_num,
		MAX(CASE WHEN f.shipping_delay_days > 0 THEN 1 ELSE 0 END)		AS order_has_late_item,
		MAX(CASE WHEN f.is_return_or_cancellation THEN 1 ELSE 0 END)	AS order_has_cancelled_item
	FROM gold.fact_order_items f
	JOIN gold.dim_date d ON f.order_date_key = d.date_key
	GROUP BY f.order_id,d.year,d.month_num
)
SELECT
	year,
	month_num,
	COUNT(*)															AS total_orders,
	SUM(CASE WHEN order_has_late_item = 0 
		AND order_has_cancelled_item = 0
		THEN 1 ELSE 0 END)												AS otif_orders,
	ROUND(100.0 * SUM(CASE WHEN order_has_late_item = 0 
						AND order_has_cancelled_item = 0
						THEN 1 ELSE 0 END) / COUNT(*) ,2)				AS otif_rate_pct
FROM order_level
GROUP BY year, month_num;

-- 2. Shipping & Logistics Cost Efficiency
-- KPI 2.1 - Freight/Fulfillment Cost proxy per Order
CREATE VIEW gold.vw_shipping_cost_efficiency AS
SELECT
	d.year,
	d.month_num,
	sm.shipping_mode,
	g.market,
	COUNT(*)			AS total_order_items,
	SUM(f.net_sales)		AS total_sales,
	SUM(f.profit_per_order)	AS total_profit,
	ROUND(SUM(f.profit_per_order) / NULLIF(SUM(f.net_sales),0) * 100 ,2)	AS profit_margin_pct,
	ROUND(AVG(f.discount_rate) * 100,2)									AS avg_discount_rate,
	ROUND(SUM(f.net_sales) / NULLIF(SUM(f.order_quantity),0) ,2)	AS avg_revenue_per_unit
FROM gold.fact_order_items f
JOIN gold.dim_date d ON f.order_date_key = d.date_key
JOIN gold.dim_shipping_mode sm ON f.shipping_mode_key = sm.shipping_mode_key
JOIN gold.dim_geography g ON f.geography_key = g.geography_key
WHERE f.is_return_or_cancellation = FALSE
GROUP BY d.year, d.month_num, sm.shipping_mode, g.market;

-- 3. Inventory / Product Movement Efficiency
-- (this dataset does not include warehouse stock-on-hand data, so true "inventory turnover"
-- in the strick finance sense is not computable. i substituted the accepted proxy
-- used when stock data is unavailable: net_seles velocity by product/category)

-- KPI 3.1 - Product Sales Velocity & Category Performance 
-- sales velocity (units/day) = total unitys sold in period / bumber of days in period
CREATE VIEW gold.vw_product_velocity AS
SELECT
	p.category_name,
	p.department_name,
	d.year,
	d.month_num,
	COUNT(DISTINCT d.full_date)				AS active_days,  -- counts actual selling days
	SUM(f.order_quantity)					AS total_units_sold,
	ROUND(SUM(f.order_quantity)::NUMERIC / NULLIF(COUNT(DISTINCT d.full_date),0),2) AS sales_velocity_unit_per_day,
	SUM(f.net_sales)						AS total_sales,
	RANK() OVER(
		PARTITION BY d.year, d.month_num
		ORDER BY SUM(f.net_sales) DESC
	)										AS category_rank_by_sales
FROM gold.fact_order_items f
JOIN gold.dim_date d ON f.order_date_key = d.date_key
JOIN gold.dim_product p ON f.product_key = p.product_key
WHERE f.is_return_or_cancellation = FALSE
GROUP BY p.category_name, p.department_name, d.year, d.month_num;


-- 4 Customer & Regional Performance
-- KPI 4.1 - Sales, Orders & Lead Time by Region/Segment
-- Avg Order-to-Delivery Lead Time = AVG(Days_for_shipping_real)
CREATE VIEW gold.vw_regional_performance AS
SELECT
	g.market,
	g.order_region,
	g.order_country,
	c.customer_segment,
	COUNT(DISTINCT f.order_id)				AS total_orders,
	COUNT(*)								AS total_order_items,
	SUM(f.net_sales)						AS total_sales,
	SUM(f.profit_per_order)					AS total_profit,
	ROUND(AVG(f.days_shipping_actual),2)	AS avg_lead_time_days,
	ROUND(
		100.0 * SUM(CASE WHEN is_late_delivery THEN 1 ELSE 0 END) 
		/ COUNT(*),2)						AS late_delivery_rate
FROM gold.fact_order_items f
JOIN gold.dim_geography g	ON f.geography_key = g.geography_key
JOIN gold.dim_customer c	ON f.customer_key = c.customer_key
WHERE f.is_return_or_cancellation = FALSE
GROUP BY g.market,	g.order_region, g.order_country, c.customer_segment;

-- Validating KPI Views
SELECT * FROM gold.vw_delivery_performance 
ORDER BY year, month_num 
LIMIT 20;

SELECT * FROM gold.vw_otif 
ORDER BY year, month_num;

SELECT * FROM gold.vw_shipping_cost_efficiency
ORDER BY year, month_num 
LIMIT 20;

SELECT * FROM gold.vw_product_velocity 
WHERE category_rank_by_sales <= 5
ORDER BY year, month_num, category_rank_by_sales;

SELECT * FROM gold.vw_regional_performance
ORDER BY total_sales DESC
LIMIT 20;

--  lightweight "flat" export view (optional, but useful for validation & quick load testing)
CREATE VIEW gold.vw_powerbi_export AS
SELECT
    f.order_item_id,
    f.order_id,
    d.full_date        AS order_date,
    sd.full_date        AS shipping_date,
    c.customer_segment,
    c.customer_country,
    p.category_name,
    p.department_name,
    g.market,
    g.order_region,
    g.order_country,
    sm.shipping_mode,
    f.net_sales,
    f.order_quantity,
    f.profit_per_order,
    f.discount_amount,
    f.days_shipping_actual,
    f.days_shipping_scheduled,
    f.shipping_delay_days,
    f.is_late_delivery,
    f.is_return_or_cancellation,
    f.delivery_status,
    f.order_status
FROM gold.fact_order_items f
JOIN gold.dim_date d        ON f.order_date_key = d.date_key
JOIN gold.dim_date sd       ON f.shipping_date_key = sd.date_key
JOIN gold.dim_customer c    ON f.customer_key = c.customer_key
JOIN gold.dim_product p     ON f.product_key = p.product_key
JOIN gold.dim_geography g   ON f.geography_key = g.geography_key
JOIN gold.dim_shipping_mode sm ON f.shipping_mode_key = sm.shipping_mode_key;

-- Confirming existing indexes
SELECT tablename, indexname, indexdef 
FROM pg_indexes 
WHERE schemaname = 'gold';

-- composite indexes for our heaviest KPI view filters
CREATE INDEX idx_fact_order_date_geo ON gold.fact_order_items(order_date_key, geography_key);

-- is_return_or_cancellation = FALSE — indexing a boolean flag used in almost every query's WHERE
CREATE INDEX idx_fact_return_flag ON gold.fact_order_items(is_return_or_cancellation);

--######################################################
-- Security/permissions layer 
--######################################################

-- Create a read-only role representing "Power BI service account" / BI consumers
CREATE ROLE bi_reader LOGIN PASSWORD 'logistics';

-- Grant access only to Gold schema — never Bronze/Silver
GRANT USAGE ON SCHEMA gold TO bi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO bi_reader;

-- Ensure future tables in gold also auto-grant (so you don't forget later)
ALTER DEFAULT PRIVILEGES IN SCHEMA gold GRANT SELECT ON TABLES TO bi_reader;


-- ##################################################
-- Final pre-BI checklist
-- ##################################################

-- 1. Confirm all Gold tables/views exist and are populated
SELECT table_name, table_type 
FROM information_schema.tables 
WHERE table_schema = 'gold'
ORDER BY table_type, table_name;

-- 2. Row counts across the whole Gold layer
SELECT 'fact_order_items' AS tbl, COUNT(*) FROM gold.fact_order_items
UNION ALL SELECT 'dim_customer', COUNT(*) FROM gold.dim_customer
UNION ALL SELECT 'dim_product', COUNT(*) FROM gold.dim_product
UNION ALL SELECT 'dim_geography', COUNT(*) FROM gold.dim_geography
UNION ALL SELECT 'dim_shipping_mode', COUNT(*) FROM gold.dim_shipping_mode
UNION ALL SELECT 'dim_date', COUNT(*) FROM gold.dim_date;

-- 3. Confirming bi_reader can actually query (test as that role, or via GRANT check)
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'bi_reader' AND table_schema = 'gold';