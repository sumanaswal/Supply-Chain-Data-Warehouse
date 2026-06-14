-- ==============================================================================
-- 1. POPULATING THE CUSTOMER DIMENSION
-- ==============================================================================
-- We use DISTINCT because the flat file repeats customer details for every item they buy.
INSERT INTO dim_customers (
    customer_id, customer_fname, customer_lname, customer_segment, 
    customer_city, customer_state, customer_country, customer_zipcode
)
SELECT DISTINCT
	CAST(customer_id AS INT),
	TRIM(customer_fname),
	TRIM(customer_lname),
	TRIM(customer_segment),
	TRIM(customer_city),
	TRIM(customer_state),
	TRIM(customer_country),
	TRIM(customer_zipcode)
FROM staging_dataco
WHERE customer_id IS NOT NULL;

-- ==============================================================================
-- 2. POPULATING THE PRODUCT DIMENSION
-- ==============================================================================
INSERT INTO dim_products (
    product_card_id, category_id, category_name, 
    product_name, product_price, product_status
)
SELECT DISTINCT
	CAST(product_card_id AS INT),
	CAST(category_id AS INT),
	TRIM(category_name),
	TRIM(product_name),
	CAST(product_price AS DECIMAL(10,2)),
	TRIM(product_status)	
FROM staging_dataco
WHERE product_card_id IS NOT NULL;

-- ==============================================================================
-- 3. POPULATING THE FACT TABLE (Transactions)
-- ==============================================================================
INSERT INTO fact_orders (
    order_id, order_item_id, customer_id, product_card_id, order_date, 
    shipping_date, order_item_quantity, order_item_discount_rate, 
    order_item_total, shipping_mode, delivery_status, late_delivery_risk
)
SELECT
	CAST(order_id AS INT),
	CAST(order_item_id AS INT),
	CAST(customer_id AS INT),
	CAST(product_card_id AS INT),

	--Converting string dates to actual timestamps ( if this does not work run the next one below)
	--CAST(order_date_dateorder AS TIMESTAMP) AS order_date,
	--CAST(shipping_date_dateorder AS TIMESTAMP) AS shipping_date,

	--EXPLICIT DATE PARSING: Telling Postgres exactly where the month, day, year, and minute are.
	TO_TIMESTAMP(order_date_dateorder, 'MM-DD-YYYY HH24.MI')  AS order_date,
	TO_TIMESTAMP(shipping_date_dateorder, 'MM-DD-YYYY HH24.MI')  AS shipping_date,
	
	CAST(order_item_quantity AS INT),
	CAST(order_item_discount_rate AS DECIMAL(5,4)),
	CAST(order_item_total AS DECIMAL(10,2)),
	TRIM(shipping_mode),
	TRIM(delivery_status),
	CAST(late_delivery_risk AS INT)
FROM staging_dataco
-- critical data quality filters
WHERE 
	-- 1. prevent time-travel: filter out any row where shipping happened before ordering
	TO_TIMESTAMP(shipping_date_dateorder, 'MM-DD-YYYY HH24.MI') >= TO_TIMESTAMP(order_date_dateorder, 'MM-DD-YYYY HH24.MI')
	-- 2. prevent ghost orders: quantity must be valid
	AND CAST(order_item_quantity AS INT) > 0;


