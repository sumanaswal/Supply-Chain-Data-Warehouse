DROP TABLE IF EXISTS bronze.data_profiling_log;

CREATE TABLE bronze.data_profiling_log (
    check_name       TEXT,
    check_category   TEXT,      -- Completeness / Uniqueness / Validity / Consistency / Accuracy
    issue_count      BIGINT,
    checked_on       TIMESTAMP DEFAULT NOW(),
    notes            TEXT
);


INSERT INTO bronze.data_profiling_log (check_name, check_category, issue_count, notes)

-- ===================== COMPLETENESS =====================
SELECT 'null_order_id', 'Completeness', COUNT(*) - COUNT("Order_Id"),
       'Order_Id is the fact grain key; nulls here would break joins downstream'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_customer_id', 'Completeness', COUNT(*) - COUNT("Order_Customer_Id"),
       'Customer_Id required for Dim_Customer join; checked for gaps'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_order_date', 'Completeness', COUNT(*) - COUNT("order_date"),
       'Rows with null order_date excluded from Silver (unusable for time-based KPIs), moved to orders_excluded_no_dates'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_shipping_date', 'Completeness', COUNT(*) - COUNT("shipping_date"),
       'Rows with null shipping_date excluded from Silver, moved to orders_excluded_no_dates'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_sales', 'Completeness', COUNT(*) - COUNT("Sales"),
       'Sales is core revenue metric; any nulls investigated before Silver load'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_quantity', 'Completeness', COUNT(*) - COUNT("Order_Item_Quantity"),
       'Order_Item_Quantity required for volume-based KPIs'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_product_price', 'Completeness', COUNT(*) - COUNT("Order_Item_Product_Price"),
       'Required for freight/unit cost KPIs'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_delivery_status', 'Completeness', COUNT(*) - COUNT("Delivery_Status"),
       'Core categorical outcome field for delivery performance KPIs'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_order_zipcode', 'Completeness', COUNT(*) - COUNT("Order_Zipcode"),
       'Not used in any KPI; left NULL in Silver, no imputation performed'
FROM bronze.orders_raw

UNION ALL
SELECT 'null_customer_zipcode', 'Completeness', COUNT(*) - COUNT("Customer_Zipcode"),
       'Minor gaps; left NULL, not core to KPI pillars'
FROM bronze.orders_raw

-- ===================== UNIQUENESS =====================
UNION ALL
SELECT 'duplicate_order_item_id', 'Uniqueness',
       COUNT(*) - COUNT(DISTINCT "Order_Item_Id"),
       'Order_Item_Id is the intended grain/primary key candidate for fact table; deduplicated via ROW_NUMBER/DISTINCT ON in Silver'
FROM bronze.orders_raw

UNION ALL
SELECT 'full_row_duplicates', 'Uniqueness',
       (SELECT COUNT(*) FROM bronze.orders_raw) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM bronze.orders_raw) t),
       'Full-row duplicate check across all columns; no material duplication expected'

-- ===================== VALIDITY =====================
UNION ALL
SELECT 'non_numeric_sales', 'Validity',
       COUNT(*) FILTER (WHERE "Sales" !~ '^-?\d+(\.\d+)?$'),
       'Rows where Sales does not match numeric pattern; would fail direct cast'
FROM bronze.orders_raw

UNION ALL
SELECT 'non_numeric_quantity', 'Validity',
       COUNT(*) FILTER (WHERE "Order_Item_Quantity" !~ '^-?\d+$'),
       'Rows where Order_Item_Quantity does not match integer pattern'
FROM bronze.orders_raw

UNION ALL
SELECT 'invalid_order_date_format', 'Validity',
       COUNT(*) FILTER (WHERE "order_date" !~ '^\d{1,2}/\d{1,2}/\d{4}'),
       'Rows where order_date does not match expected MM/DD/YYYY pattern'
FROM bronze.orders_raw

UNION ALL
SELECT 'negative_quantity_or_sales', 'Validity',
       COUNT(*) FILTER (WHERE "Order_Item_Quantity" ~ '^-?\d+$' AND "Order_Item_Quantity"::NUMERIC < 0
                          OR "Sales" ~ '^-?\d+(\.\d+)?$' AND "Sales"::NUMERIC < 0),
       'Negative values represent returns/cancellations, not data errors; flagged via is_return_or_cancellation column in Silver rather than deleted'
FROM bronze.orders_raw

-- ===================== CONSISTENCY =====================
UNION ALL
SELECT 'categorical_variants_delivery_status', 'Consistency',
       COUNT(DISTINCT "Delivery_Status"),
       'Distinct value count for Delivery_Status; standardized via TRIM + INITCAP in Silver'
FROM bronze.orders_raw

UNION ALL
SELECT 'categorical_variants_shipping_mode', 'Consistency',
       COUNT(DISTINCT "Shipping_Mode"),
       'Distinct value count for Shipping_Mode; standardized via TRIM + INITCAP in Silver'
FROM bronze.orders_raw

UNION ALL
SELECT 'categorical_variants_order_status', 'Consistency',
       COUNT(DISTINCT "Order_Status"),
       'Includes business-relevant value SUSPECTED_FRAUD; standardized casing via UPPER, retained as valid category not an error'
FROM bronze.orders_raw

-- ===================== ACCURACY =====================
UNION ALL
SELECT 'late_delivery_risk_vs_actual_mismatch', 'Accuracy',
       COUNT(*) FILTER (WHERE "Late_delivery_risk"::INT = 0
                           AND "Days_for_shipping_real"::INT > "Days_for_shipment_scheduled"::INT),
       'Late_delivery_risk is a pre-built ML label, not a live outcome flag; disagrees materially with actual day-count outcome (Days_for_shipping_real vs Days_for_shipment_scheduled). Decision: derived field is_late_delivery used as sole KPI source of truth; Late_delivery_risk retained as reference attribute only, excluded from all dashboard KPIs.'
FROM bronze.orders_raw
WHERE "Days_for_shipping_real" ~ '^\d+$' AND "Days_for_shipment_scheduled" ~ '^\d+$' AND "Late_delivery_risk" ~ '^\d+$'

UNION ALL
SELECT 'sales_formula_mismatch', 'Accuracy',
       COUNT(*) FILTER (WHERE ROUND("Sales"::NUMERIC,2) <>
                         ROUND("Order_Item_Product_Price"::NUMERIC * "Order_Item_Quantity"::NUMERIC * (1 - "Order_Item_Discount_Rate"::NUMERIC),2)),
       'Sales does not always equal Price*Qty*(1-Discount); Sales column trusted as-reported rather than recomputed from components'
FROM bronze.orders_raw
WHERE "Sales" ~ '^-?\d+(\.\d+)?$' AND "Order_Item_Product_Price" ~ '^-?\d+(\.\d+)?$'
  AND "Order_Item_Quantity" ~ '^\d+$' AND "Order_Item_Discount_Rate" ~ '^-?\d+(\.\d+)?$'

UNION ALL
SELECT 'shipping_before_order_date', 'Accuracy',
       COUNT(*) FILTER (WHERE TO_DATE("shipping_date",'MM/DD/YYYY HH24:MI') < TO_DATE("order_date",'MM/DD/YYYY HH24:MI')),
       'Checks that shipping_date never precedes order_date; validates date logic integrity'
FROM bronze.orders_raw
WHERE "order_date" ~ '^\d{1,2}/\d{1,2}/\d{4}' AND "shipping_date" ~ '^\d{1,2}/\d{1,2}/\d{4}';

-- 
INSERT INTO bronze.data_profiling_log (check_name, check_category, issue_count, notes)
VALUES (
    'sales_column_is_gross_not_net',
    'Accuracy',
    (SELECT COUNT(*) FROM bronze.orders_raw WHERE "Order_Item_Discount"::NUMERIC(12,2) > 0),
    'Sales column represents gross revenue (Price x Quantity) BEFORE discount, not net revenue. Order_Item_Total = Sales - Order_Item_Discount is the correct net/realized revenue figure. Decision: renamed to gross_sales and net_sales in Gold layer respectively; all dashboard "Total Revenue" KPIs must use net_sales, not gross_sales, to avoid overstating realized revenue.'
);
-- Compelete report
SELECT *
FROM bronze.data_profiling_log
