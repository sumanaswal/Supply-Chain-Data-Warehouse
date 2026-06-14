-- ==============================================================
-- 1. STAGING TABLE: The landing zone for raw CSV data.
-- ==============================================================
-- we drop the table if it exists so our pipeline can be re-run safely 
DROP TABLE IF EXISTS staging_dataco;

CREATE TABLE staging_dataco (
	type VARCHAR(50),
	days_for_shipping_real VARCHAR(50),
	days_for_shipment_scheduled VARCHAR(50),
	benefit_per_order VARCHAR(50),
	sales_per_customer VARCHAR(50),
	delivery_status VARCHAR(50),
	late_delivery_risk VARCHAR(50),
	category_id VARCHAR(50),
	category_name VARCHAR(150),
	customer_city VARCHAR(150),
	customer_country VARCHAR(50),
	customer_email VARCHAR(50),
	customer_fname VARCHAR(50),
	customer_id VARCHAR(50),
	customer_lname VARCHAR(50),
	customer_password VARCHAR(50),
	customer_segment VARCHAR(50),
	customer_state VARCHAR(50),
	customer_street VARCHAR(150),
	customer_zipcode VARCHAR(50),
	department_id VARCHAR(50),
	department_name VARCHAR(50),
	latitude VARCHAR(50),
	longitude VARCHAR(50),
	market VARCHAR(50),
	order_city VARCHAR(100),
	order_country VARCHAR(100),
	order_customer_id VARCHAR(50),
	order_date_dateOrder VARCHAR(50),
	order_id VARCHAR(50),
	order_item_cardprod_id VARCHAR(50),
	order_item_discount VARCHAR(50),
	order_item_discount_rate VARCHAR(50),
	order_item_id VARCHAR(50),
	order_item_product_price VARCHAR(50),
	order_item_profit_ratio VARCHAR(50),
	order_item_quantity VARCHAR(50),
	sales VARCHAR(50),
	order_item_total VARCHAR(50),
	order_profit_per_order VARCHAR(50),
	order_region VARCHAR(50),
	order_state VARCHAR(100),
	order_status VARCHAR(50),
	order_zipcode VARCHAR(50),
	product_card_id VARCHAR(50),
	product_category_id VARCHAR(50),
	product_description VARCHAR(50),
	product_image VARCHAR(200),
	product_name VARCHAR(200),
	product_price VARCHAR(50),
	product_status VARCHAR(50),
	shipping_date_dateOrder VARCHAR(50),
	shipping_mode VARCHAR(50)
);

-- =======================================================
-- 2. BULK INGESTION: loading the flate file
-- =======================================================
-- copy command is the industry standard for fast bulk ingestion in Postgres.
-- if the below command does not work then use the import export data wizard by RC on table name (staging_dataco)
COPY staging_dataco
FROM '../data/orders.csv'
DELIMITER ','
CSV HEADER
ENCODING 'LATIN1'; -- the kaggle dataset contains spanish/french characters accents

-- =============================================================================
-- 3. Dimension table: Customers (master record of buyers)
-- =============================================================================
CREATE TABLE dim_customers (
	customer_id INT PRIMARY KEY,
	customer_fname VARCHAR(50),
	customer_lname VARCHAR(50),
	customer_segmnet VARCHAR(50),
	customer_city VARCHAR(50),
	customer_state VARCHAR(50),
	customer_country VARCHAR(50),
	customer_zipcode VARCHAR(50)
);

-- ==============================================================================
-- 2. DIMENSION TABLE: Products (Master catalog of inventory)
-- ==============================================================================
CREATE TABLE dim_products (
	product_card_id INT PRIMARY KEY,
	category_id INT,
	category_name VARCHAR(100),
	product_name VARCHAR(250),
	product_price DECIMAL(10,2),
	product_status VARCHAR(50)
);

-- ==============================================================================
-- 3. FACT TABLE: Orders & Logistics (Transactional core)
-- ==============================================================================
CREATE TABLE fact_orders (
	order_id INT,
	order_item_id INT PRIMARY KEY, -- datset granularity is at the order-item
	customer_id INT,
	product_card_id INT,
	order_date TIMESTAMP,
	shipping_date TIMESTAMP,
	order_item_quantity INT,
	order_item_discount_rate DECIMAL(5,4),
	order_item_total DECIMAL(10,2),
	shipping_mode VARCHAR(50),
	delivery_status VARCHAR(50),
	late_delivery_risk INT CHECK (late_delivery_risk IN (0,1)),

	-- RELATIONAL INTEGRITY: ensure every order maps to a valid customer and product
	CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id),
	CONSTRAINT fk_product FOREIGN KEY (product_card_id) REFERENCES dim_products(product_card_id),

	-- CHRONOLOGICAL CONSISTENCY: A shipment data cannot logically precede an order date.
	-- this constraint explicitly blocks time-travel data anamolies at the database level.
	CONSTRAINT chk_chronology CHECK (shipping_date >= order_date),

	-- BUSINESS LOGIC: you cannot sell 0 or negetive items
	CONSTRAINT chk_quantity CHECK (order_item_quantity > 0)
	
);

