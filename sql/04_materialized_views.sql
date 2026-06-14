-- ==============================================================================
-- 1. OPERATIONS & LOGISTICS DATA MART (For the Supply Chain Dashboard)
-- ==============================================================================
-- This view flattens the Star Schema specifically for tracking SLAs and bottlenecks.
CREATE MATERIALIZED VIEW mv_supply_chain_operation AS
SELECT
	f.order_id,
	f.order_item_id,
	f.order_date,
	f.shipping_date,

	-- calculating actual physical shipping duration
	EXTRACT(DAY FROM f.shipping_date - f.order_date) AS actual_shipping_days,

	f.shipping_mode,
	f.delivery_status,
	f.late_delivery_risk,

	p.category_name,
	p.product_name,

	c.customer_city,
	c.customer_state,
	c.customer_country
FROM fact_orders f
JOIN dim_products p ON p.product_card_id = f.product_card_id 
JOIN dim_customers c ON c.customer_id = f.customer_id;

-- ==============================================================================
-- 2. EXECUTIVE FINANCIALS & SEGMENTATION (For the Sales Dashboard)
-- ==============================================================================
-- This view aggregates the heavy financial math and RFM scoring we built earlier.
CREATE MATERIALIZED VIEW mv_executive_financials AS
WITH BaseFinancials AS (
    SELECT 
        f.customer_id,
        f.order_id,
        f.order_date,
        p.category_name,
        f.order_item_quantity,
        f.order_item_total AS gross_revenue,
        (f.order_item_total * f.order_item_discount_rate) AS discount_amount,
        (f.order_item_total - (f.order_item_total * f.order_item_discount_rate)) AS net_revenue
    FROM fact_orders f
    JOIN dim_products p ON f.product_card_id = p.product_card_id
)
SELECT 
    bf.order_date,
    bf.category_name,
    c.customer_segment,
    c.customer_country,
    SUM(bf.order_item_quantity) AS total_units_sold,
    SUM(bf.gross_revenue) AS total_gross_revenue,
    SUM(bf.discount_amount) AS total_discounts_given,
    SUM(bf.net_revenue) AS total_net_revenue,
    ROUND((SUM(bf.net_revenue) / NULLIF(SUM(bf.gross_revenue), 0)) * 100, 2) AS profit_margin_percent
FROM BaseFinancials bf
JOIN dim_customers c ON bf.customer_id = c.customer_id
GROUP BY 
    bf.order_date, 
    bf.category_name, 
    c.customer_segment, 
    c.customer_country;

-- ==============================================================================
-- 3. INDEXING THE VIEWS (Performance Optimization)
-- ==============================================================================
-- Materialized views act like tables, so we index the most commonly filtered columns
-- to ensure Power BI loads the visuals instantly.
CREATE INDEX idx_mv_supply_date ON mv_supply_chain_operation(order_date);
CREATE INDEX idx_mv_exec_date ON mv_executive_financials(order_date);