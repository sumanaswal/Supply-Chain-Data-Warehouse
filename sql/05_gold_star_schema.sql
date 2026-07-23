--############################################################
-- GOLD LAYER - Start Schema ( Fact & Dimension Tables)
--############################################################

-- This is the layer Power BI will actually connect to. one central fact table (the measurable business events)
-- surrounded by Dimension tables ( descriptive context)

-- dim_date ( building manually)
CREATE TABLE gold.dim_date (
	date_key		INT PRIMARY KEY,	-- format YYYYMMDD, e.g. 20260131
	full_date		DATE NOT NULL,
	day_of_week		INT,
	day_name		TEXT,
	day_of_month	INT,
	week_of_year	INT,
	month_num		INT,
	month_name		TEXT,
	quarter			INT,
	year			INT,
	is_weekend		BOOLEAN
);

-- inserting data into dim_date 
INSERT INTO gold.dim_date
SELECT
	TO_CHAR(d, 'YYYYMMDD')::INT			AS date_key,
	d									AS full_date,
	EXTRACT(ISODOW FROM d)::INT			AS day_of_week,
	TO_CHAR(d, 'Day')					AS day_name,
	EXTRACT(DAY FROM d)::INT			AS day_of_month,
	EXTRACT(WEEK FROM d)::INT			AS week_of_year,
	EXTRACT(MONTH FROM d)::INT			AS month_num,
	TO_CHAR(d, 'Month')					AS month_name,
	EXTRACT(QUARTER FROM d)::INT		AS quarter,
	EXTRACT(YEAR FROM d)::INT			AS year,
	EXTRACT(ISODOW FROM D) IN (6,7)		AS is_weekend
FROM generate_series(
	'2015-01-01'::DATE,
	'2018-12-31'::DATE,
	'1 day'::INTERVAL
	) AS d;

-- dim_customer
CREATE TABLE gold.dim_customer (
	customer_key		SERIAL PRIMARY KEY,
	customer_id			INT UNIQUE,
	customer_fname		TEXT,
	customer_lname		TEXT,
	customer_segment	TEXT,
	customer_city		TEXT,
	customer_state		TEXT,
	customer_country	TEXT
);

-- Loading data into dim_customer
INSERT INTO gold.dim_customer(customer_id, customer_fname, customer_lname, customer_segment, customer_city, customer_state, customer_country)
SELECT DISTINCT
	customer_id,
	customer_fname,
	customer_lname,
	customer_segment,
	customer_city,
	customer_state,
	customer_country
FROM silver.orders_clean;


-- dim_product
CREATE TABLE gold.dim_product (
    product_key     SERIAL PRIMARY KEY,
    product_id		INT UNIQUE,
	product_name	TEXT,
    category_id     INT,
    category_name   TEXT,
    department_id   INT,
    department_name TEXT,
    product_price   NUMERIC(12,2)
);

-- DISTINCT ON forces exactlly one deterministic row per product_id
-- picking the lowest price version perthe ORDER BY
INSERT INTO gold.dim_product (product_id, product_name, category_id, category_name, department_id, department_name, product_price)
SELECT DISTINCT ON (product_id)
    product_id,
	product_name,
    category_id,
    category_name,
    department_id,
    department_name,
    product_price
FROM silver.orders_clean
ORDER BY product_id, product_price;  -- if a product has fluctuating price rows, we take a consistent one deterministically

-- dim_geography
CREATE TABLE gold.dim_geography (
    geography_key   SERIAL PRIMARY KEY,
    order_city      TEXT,
    order_state     TEXT,
    order_country   TEXT,
    order_region    TEXT,
    market          TEXT
);

-- loading data into dim_geography
INSERT INTO gold.dim_geography (order_city, order_state, order_country, order_region, market)
SELECT DISTINCT
    order_city,
	order_state,
	order_country,
	order_region,
	market
FROM silver.orders_clean;

-- dim_shipping_mode
CREATE TABLE gold.dim_shipping_mode (
    shipping_mode_key SERIAL PRIMARY KEY,
    shipping_mode      TEXT UNIQUE
);

INSERT INTO gold.dim_shipping_mode (shipping_mode)
SELECT DISTINCT shipping_mode FROM silver.orders_clean;


-- Fact Table
CREATE TABLE gold.fact_order_items (
	order_item_id		INT PRIMARY KEY,	--grain key
	order_id			INT,
	customer_key		INT REFERENCES gold.dim_customer(customer_key),
	product_key			INT REFERENCES gold.dim_product(product_key),
	geography_key		INT REFERENCES gold.dim_geography(geography_key),
	shipping_mode_key	INT REFERENCES gold.dim_shipping_mode(shipping_mode_key),
	order_date_key		INT	REFERENCES gold.dim_date(date_key),
	shipping_date_key	INT REFERENCES gold.dim_date(date_key),

	-- Measures (additive facts)
	gross_sales					NUMERIC(12,2),
	discount_amount 			NUMERIC(12,2),
	net_sales 					NUMERIC(12,2),
	order_quantity				INT,
	discount_rate				NUMERIC(5,4),
	profit_per_order			NUMERIC(12,2),
	days_shipping_actual		INT,
	days_shipping_scheduled		INT,
	shipping_delay_days			INT,

	-- Flags (for filtering, not aggregation)
	is_late_delivery			BOOLEAN,
	is_return_or_cancellation	BOOLEAN,
	delivery_status				TEXT,
	order_status				TEXT
);

INSERT INTO gold.fact_order_items
SELECT
	s.order_item_id,
	s.order_id,
	c.customer_key,
	p.product_key,
	g.geography_key,
	sm.shipping_mode_key,
	TO_CHAR(s.order_date, 'YYYYMMDD')::INT,
	TO_CHAR(s.shipping_date, 'YYYYMMDD')::INT,
	s.gross_sales,
	s.discount_amount,
	s.net_sales,
	s.order_quantity,
	s.discount_rate,
	s.profit_per_order,
	s.days_shipping_actual,
	s.days_shipping_scheduled,
	s.shipping_delay_days,
	s.is_late_delivery,
	s.is_return_or_cancellation,
	s.delivery_status,
	s.order_status
FROM silver.orders_clean s
LEFT JOIN gold.dim_customer c	ON s.customer_id = c.customer_id
LEFT JOIN gold.dim_product p	ON s.product_id	= p.product_id
LEFT JOIN gold.dim_geography g	ON s.order_city = g.order_city
									AND s.order_state = g.order_state
									AND s.order_country = g.order_country
									AND s.order_region = g.order_region
									AND s.market = g.market
LEFT JOIN gold.dim_shipping_mode sm	ON s.shipping_mode = sm.shipping_mode;


-- Validating the Star Schema
-- row count parity check
SELECT
	(SELECT COUNT(*) FROM silver.orders_clean)		AS silver_rows,
	(SELECT COUNT(*) FROM gold.fact_order_items)	AS fact_rows;

-- Referential integrity: any unmatched dimension keys?
SELECT COUNT(*) FROM gold.fact_order_items WHERE customer_key IS NULL;
SELECT COUNT(*) FROM gold.fact_order_items WHERE product_key IS NULL;
SELECT COUNT(*) FROM gold.fact_order_items WHERE geography_key IS NULL;
SELECT COUNT(*) FROM gold.fact_order_items WHERE shipping_mode_key IS NULL;
SELECT COUNT(*) FROM gold.fact_order_items WHERE order_date_key IS NULL;

-- Quick sanity aggregate: total sales should match silver total
SELECT SUM(net_sales) FROM gold.fact_order_items;
SELECT SUM(net_sales) FROM silver.orders_clean;


-- Indexs (performance - Power BI will query this table constantly)
CREATE INDEX idx_fact_customer_key ON gold.fact_order_items(customer_key);
CREATE INDEX idx_fact_product_key ON gold.fact_order_items(product_key);
CREATE INDEX idx_fact_geography_key ON gold.fact_order_items(geography_key);
CREATE INDEX idx_fact_order_date_key ON gold.fact_order_items(order_date_key);
CREATE INDEX idx_fact_shipping_mode_key ON gold.fact_order_items(shipping_mode_key);