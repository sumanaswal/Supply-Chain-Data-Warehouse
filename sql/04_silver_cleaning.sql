-- ##############################################
-- Silver Layer — Data Cleaning & Transformation
-- ##############################################

-- 1. Deduplication (based on data profiling)
-- keeps only one row per group based on order by
CREATE TABLE silver.orders_dedup AS
SELECT DISTINCT ON ("Order_Item_Id") *
FROM bronze.orders_raw
ORDER BY "Order_Item_Id", "order_date" DESC;

-- Safe type casting
-- validate before casting and route invalid value to null rather then breaking the whole pipeline
CREATE TABLE silver.orders_clean AS
SELECT
	-- identifiers
	"Order_Item_Id"::INT							AS order_item_id,
	"Order_Id"::INT									AS order_id,
	"Order_Customer_Id"::INT                       AS customer_id,
    "Product_Card_Id"::INT                         AS product_id,
    "Category_Id"::INT                             AS category_id,
    "Department_Id"::INT                           AS department_id,

	-- Dates safe cast using CASE + regex validation
	CASE WHEN "order_date" ~ '^\d{1,2}/\d{1,2}/\d{4}'
		THEN TO_DATE("order_date",'MM/DD/YYYY HH24:MI')
		ELSE NULL END								AS order_date,
	CASE WHEN "shipping_date" ~'^\d{1,2}/\d{1,2}/\d{4}'
		THEN TO_DATE("shipping_date",'MM/DD/YYYY HH24:MI')
		ELSE NULL END								AS shipping_date,

	-- Numerics: safe cast using regex guard
	CASE WHEN "Sales" ~ '^-?\d+(\.\d+)?$'
		THEN "Sales"::NUMERIC(12,2) ELSE NULL END	AS gross_sales,
	CASE WHEN "Order_Item_Discount" ~ '^-?\d+(\.\d+)?$' 
		THEN "Order_Item_Discount"::NUMERIC(12,2) ELSE NULL END		AS discount_amount,
	CASE WHEN "Order_Item_Total" ~ '^-?\d+(\.\d+)?$' 
		THEN "Order_Item_Total"::NUMERIC(12,2) ELSE NULL END		AS net_sales,
	CASE WHEN "Order_Item_Quantity" ~ '^\d+$'
		THEN "Order_Item_Quantity"::INT ELSE NULL END	AS order_quantity,
	CASE WHEN "Order_Item_Product_Price" ~ '^-?\d+(\.\d+)?$'
		THEN "Order_Item_Product_Price"::NUMERIC(12,2) ELSE NULL END	AS product_price,
	CASE WHEN "Order_Item_Discount_Rate" ~ '^-?\d+(\.\d+)?$' 
         THEN "Order_Item_Discount_Rate"::NUMERIC(5,4) ELSE NULL END AS discount_rate,
    CASE WHEN "Order_Profit_Per_Order" ~ '^-?\d+(\.\d+)?$' 
         THEN "Order_Profit_Per_Order"::NUMERIC(12,2) ELSE NULL END AS profit_per_order,
    CASE WHEN "Days_for_shipping_real" ~ '^\d+$' 
         THEN "Days_for_shipping_real"::INT ELSE NULL END AS days_shipping_actual,
    CASE WHEN "Days_for_shipment_scheduled" ~ '^\d+$' 
         THEN "Days_for_shipment_scheduled"::INT ELSE NULL END AS days_shipping_scheduled,
    "Late_delivery_risk"::INT                       AS late_delivery_risk_flag,

	-- Text/categorical (standardized in step 3 below, raw for now)
    "Delivery_Status"		AS delivery_status,
    "Shipping_Mode"       	AS shipping_mode,
    "Order_Status"        	AS order_status,
    "Customer_Segment"    	AS customer_segment,
	"Product_Name"			AS product_name,
    "Category_Name"       	AS category_name,
    "Department_Name"    	AS department_name,
    "Market"              	AS market,
    "Order_Region"        	AS order_region,
    "Order_Country"       	AS order_country,
    "Order_State"         	AS order_state,
    "Order_City"          	AS order_city,
	"Customer_Fname"		AS customer_fname,
	"Customer_Lname"		AS customer_lname,
    "Customer_City"       	AS customer_city,
    "Customer_State"      	AS customer_state,
    "Customer_Country"    	AS customer_country
FROM silver.orders_dedup;

-- Standardizing Categorica texts (fixing casing/whitespace inconsistencies)
UPDATE silver.orders_clean
SET delivery_status	= TRIM(INITCAP(delivery_status)),
	shipping_mode	= TRIM(INITCAP(shipping_mode)),
	order_status	= TRIM(UPPER(order_status)),
	customer_segment= TRIM(INITCAP(customer_segment)),
	market			= TRIM(INITCAP(market)),
	order_region	= TRIM(INITCAP(order_region)),
	product_name	= TRIM(INITCAP(product_name)),
	customer_fname	= TRIM(INITCAP(customer_fname)),
	customer_lname	= TRIM(INITCAP(customer_lname))

	
-- Handling outliers & negative values
-- we flag these rows with boolean column. this preserves data completeness
-- an easy way to build a separate returns/cancellation-rate KPI later
ALTER TABLE silver.orders_clean ADD COLUMN is_return_or_cancellation BOOLEAN;

UPDATE silver.orders_clean
SET is_return_or_cancellation = 
	CASE WHEN order_quantity < 0 OR net_sales < 0 OR order_status IN('CANCELED','SUSPECTED_FRAUD')
		THEN TRUE ELSE FALSE END;

--#####################################
-- Null Handling
--#####################################

-- zipcodes: not used in KPIs, imputing would be fabricating data
-- no action needed - already null from safe casting.

-- Dates: NULL order_date/shipping_date rows are unusable for time-based KPIs — isolate them
CREATE TABLE silver.orders_excluded_no_dates AS
SELECT * FROM silver.orders_clean
WHERE order_date IS NULL
	OR shipping_date IS NULL;

DELETE FROM silver.orders_clean
WHERE order_date IS NULL
	OR shipping_date IS NULL;

-- ##########################################################
-- Adding Derived Cleaned Columns
-- ##########################################################

-- we materialize this now rather then recalculating in every futere query
-- it is the core input to our late-delivery KPI
ALTER TABLE silver.orders_clean
	ADD COLUMN shipping_delay_days INT,
	ADD COLUMN is_late_delivery BOOLEAN;

UPDATE silver.orders_clean
SET shipping_delay_days = days_shipping_actual - days_shipping_scheduled,
	is_late_delivery = CASE WHEN days_shipping_actual > days_shipping_scheduled
							THEN TRUE ELSE FALSE END;


--############################################
-- Final Validation of Silver Layer
--#############################################

-- Row count comparison against Bronze (understanding exactly what was excluded, and why)
SELECT
	(SELECT COUNT(*) FROM bronze.orders_raw)		AS bronze_rows,
	(SELECT COUNT(*) FROM silver.orders_clean)		AS silver_rows,
	(SELECT COUNT(*) FROM silver.orders_excluded_no_dates)	AS excluede_rows;

-- Confirming no unexpected nulls remain in critical columns
SELECT COUNT(*) FROM silver.orders_clean
WHERE order_id IS NULL 
	OR customer_id IS NULL
	OR net_sales IS NULL;

-- Confirming categorical standardization worked (should show clean single variants)
SELECT DISTINCT delivery_status FROM silver.orders_clean;
SELECT DISTINCT shipping_mode FROM silver.orders_clean;



