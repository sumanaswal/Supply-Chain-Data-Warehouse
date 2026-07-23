-- Total row count (our baseline for all future comparisons)
SELECT COUNT(*) AS total_rows FROM bronze.orders_raw;

-- Column list and data types (sanity check after import)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bronze' AND table_name = 'orders_raw'
ORDER BY ordinal_position;

-- Completeness check - NULL/Blanck audit (every column, systematically)
SELECT 
	COUNT(*) 										AS total_rows,
	COUNT(*) - COUNT("Order_Id")					AS null_order_id,
	COUNT(*) - COUNT("Customer_Id")					AS null_customer_id,
	COUNT(*) - COUNT("order_date")					AS null_order_date,
	COUNT(*) - COUNT("shipping_date")				AS null_shipping_date,
	COUNT(*) - COUNT("Sales")						AS null_sales,
	COUNT(*) - COUNT("Order_Item_Quantity")			AS null_quantity,
	COUNT(*) - COUNT("Order_Item_Product_Price")	AS null_price,
	COUNT(*) - COUNT("Delivery_Status")				AS null_delivery_status,
	COUNT(*) - COUNT("Customer_Zipcode")			AS null_customer_zip,
	COUNT(*) - COUNT("Order_Zipcode")				AS null_order_zip
FROM bronze.orders_raw;

-- Uniqueness check - duplicate detection
-- Are Order_Item_Id values unique? (this should be our grain / primary key candidate)
SELECT 
	"Order_Item_Id", 
	COUNT(*) AS occurrence_count
FROM bronze.orders_raw
GROUP BY "Order_Item_Id"
HAVING COUNT(*) > 1;

-- Full row duplicate check (entire record repeated)
SELECT 
	"Order_Item_Id",
	"Order_Id",
	"Customer_Id",
	"order_date",
	"Sales",
	COUNT(*)
FROM bronze.orders_raw
GROUP BY "Order_Item_Id",
		"Order_Id",
		"Customer_Id",
		"order_date",
		"Sales"
HAVING COUNT(*) > 1;

-- Confirm grain: check if Order_Id repeats (expected) vs Order_Item_Id repeats (should not)
SELECT 
	"Order_Id",
	COUNT(DISTINCT "Order_Item_Id") AS line_items
FROM bronze.orders_raw
GROUP BY "Order_Id"
ORDER BY line_items DESC
LIMIT 10;

-- Can order_date and shipping_date safely cast to DATE? Find rows that would break casting.
SELECT 
	"order_date",
	"shipping_date"
FROM bronze.orders_raw
WHERE "order_date" !~ '^\d{1,2}/\d{1,2}/\d{4}.*$'   -- adjust pattern to your file's actual date format
	OR "shipping_date" !~ '^\d{1,2}/\d{1,2}/\d{4}.*$' 
LIMIT 20;

-- Numeric validity: Sales, Price, Quantity should be numeric — find non-numeric junk
SELECT 
	"Sales",
	"Product_Price",
	"Order_Item_Quantity"
FROM bronze.orders_raw
WHERE "Sales" !~ '^-?\d+(\.\d+)?$'
	OR "Product_Price" !~ '^-?\d+(\.\d+)?$'
	OR "Order_Item_Quantity" !~ '^-?\d+(\.\d+)?$'
LIMIT 20;

-- Range/outlier check: negative or zero sales, negative quantity, negative price
SELECT
    MIN("Sales"::NUMERIC)  						AS min_sales,
    MAX("Sales"::NUMERIC)  						AS max_sales,
	ROUND(AVG("Sales"::NUMERIC),2)				AS avg_sales,
	PERCENTILE_CONT(0.5) 
		WITHIN GROUP(ORDER BY "Sales"::NUMERIC) AS median_sale,
    MIN("Order_Item_Quantity"::NUMERIC) 		AS min_qty,
    MAX("Order_Item_Quantity"::NUMERIC) 		AS max_qty,
    MIN("Order_Item_Product_Price"::NUMERIC) 	AS min_price,
    MAX("Order_Item_Product_Price"::NUMERIC) 	AS max_price
FROM bronze.orders_raw;

-- Consistency check - categorical value Audit
SELECT
	"Delivery_Status",
	COUNT(*)
FROM bronze.orders_raw
GROUP BY "Delivery_Status"
ORDER BY COUNT(*);

SELECT
	"Shipping_Mode",
	COUNT(*)
FROM bronze.orders_raw
GROUP BY "Shipping_Mode"
ORDER BY COUNT(*);

SELECT 
	"Order_Status", 
	COUNT(*) 
FROM bronze.orders_raw 
GROUP BY "Order_Status" 
ORDER BY COUNT(*) DESC;

SELECT 
	"Market", 
	"Order_Region", 
	COUNT(*)
FROM bronze.orders_raw
GROUP BY "Market", "Order_Region"
ORDER BY "Market", "Order_Region";

SELECT 
	"Customer_Segment",
	COUNT(*) 
FROM bronze.orders_raw 
GROUP BY "Customer_Segment";

-- Logical / Referential Consistency check - cross column business logic
-- checking whether the data obeys real world logic

-- shipping date should never be before order_date (5080 orders have same order and shipping date)
SELECT
	"order_date",
	"shipping_date"
FROM bronze.orders_raw
WHERE TO_TIMESTAMP("shipping_date",'MM/DD/YYYY HH24:MI')::DATE 
	>= TO_TIMESTAMP("order_date",'MM/DD/YYYY HH24:MI')::DATE;

-- Late_delivery_risk flag should align with actual vs scheduled shipping days
SELECT
	"Late_delivery_risk",
	ROUND(AVG("Days_for_shipping_real"::numeric - "Days_for_shipment_scheduled"::numeric),2) AS avg_day_diff,
	COUNT(*)
FROM bronze.orders_raw
GROUP BY "Late_delivery_risk"

-- Actual late delivery percentage 
SELECT
    "Late_delivery_risk",
    ROUND(AVG(
        ("Days_for_shipping_real"::numeric >
         "Days_for_shipment_scheduled"::numeric)::int
    ) * 100,2) AS pct_actually_late
FROM bronze.orders_raw
GROUP BY "Late_delivery_risk";

-- Sales should equal Product_Price * Quantity * (1 - Discount_Rate) — check for mismatches
-- in this dataset Sales is the amount before discount and Order_Item_Total is the amount after discount
SELECT
	"Order_Item_Product_Price",
	"Order_Item_Quantity",
	"Order_Item_Discount",
	"Sales",
	ROUND("Order_Item_Total"::NUMERIC,2) 											AS Order_Item_Total,
	ROUND(("Order_Item_Product_Price"::NUMERIC * "Order_Item_Quantity"::NUMERIC)
		- "Order_Item_Discount"::NUMERIC,2) 										AS sales_calculattion
FROM bronze.orders_raw
LIMIT 10;
