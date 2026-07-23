# Data Dictionary — DataCo Smart Supply Chain Dataset

Source: [DataCo Smart Supply Chain for Big Data Analysis](https://www.kaggle.com/datasets/shashwatwork/dataco-smart-supply-chain-for-big-data-analysis) (Kaggle)
Raw file: `DataCoSupplyChainDataset.csv` — ~180,519 rows, one row per order line item.
Encoding: Latin-1 (ISO-8859-1). Delimiter: comma.

## Grain
One row = one product line item within one order (`Order_Item_Id` is the unique key; `Order_Id` repeats across multiple line items belonging to the same order).

## Column Reference

| Source Column | Type (raw) | Description | Used In |
|---|---|---|---|
| `Order_Item_Id` | text → int | Unique identifier for one order line item; fact table grain key | `fact_order_items.order_item_id` |
| `Order_Id` | text → int | Identifier for the parent order (repeats across line items) | `fact_order_items.order_id` |
| `order_date` | text → date | Date the order was placed | `dim_date` (via `order_date_key`) |
| `shipping_date` | text → date | Date the order was actually shipped/delivered | `dim_date` (via `shipping_date_key`, inactive relationship) |
| `Days_for_shipping_real` | text → int | Actual number of days taken to ship | `days_shipping_actual` |
| `Days_for_shipment_scheduled` | text → int | Promised/scheduled number of days for shipping | `days_shipping_scheduled` |
| `Late_delivery_risk` | text → int (0/1) | Pre-built ML label; **found to disagree with actual outcomes — excluded from all KPIs** (see data_quality_report.md) | retained as reference attribute only |
| `Delivery_Status` | text | Categorical outcome: Late delivery / Shipping on time / Advance shipping / Shipping canceled | `fact_order_items.delivery_status` |
| `Order_Status` | text | Order lifecycle status (COMPLETE, PENDING, SUSPECTED_FRAUD, CANCELED, etc.) | `fact_order_items.order_status` |
| `Order_Item_Quantity` | text → int | Units ordered for this line item | `fact_order_items.order_quantity` |
| `Order_Item_Product_Price` | text → numeric | List price per unit | `dim_product.product_price` |
| `Order_Item_Discount_Rate` | text → numeric | Discount rate applied to this line item | `fact_order_items.discount_rate` |
| `Sales` | text → numeric | Realized revenue for this line item (trusted as-reported; does not always equal Price × Qty × (1-Discount) — see data quality report) | `fact_order_items.sales` |
| `Order_Profit_Per_Order` | text → numeric | Profit for this line item | `fact_order_items.profit_per_order` |
| `Category_Id` / `Category_Name` | text | Product category | `dim_product.category_id/name` |
| `Department_Id` / `Department_Name` | text | Product department (parent of category) | `dim_product.department_id/name` |
| `Product_Card_Id` | text → int | Product identifier | `dim_product.product_id` |
| `Customer_Id` (`Order_Customer_Id`) | text → int | Customer identifier | `dim_customer.customer_id` |
| `Customer_Segment` | text | Consumer / Corporate / Home Office | `dim_customer.customer_segment` |
| `Customer_City/State/Country` | text | Customer's home address (distinct from shipping destination) | `dim_customer` |
| `Order_City/State/Country/Region` | text | Order/shipping destination | `dim_geography` |
| `Market` | text | High-level market grouping (e.g., Europe, LATAM, USCA, Pacific Asia, Africa) | `dim_geography.market` |
| `Shipping_Mode` | text | Standard Class / Second Class / First Class / Same Day | `dim_shipping_mode.shipping_mode` |
| `Customer_Zipcode` / `Order_Zipcode` | text | Postal codes — contain nulls; not used in any KPI, left NULL in Silver | not loaded into Gold |
| `Latitude` / `Longitude` | text | Geographic coordinates | not currently used |
| `Product_Description` | text | Product description text — mostly null in source | not loaded into Gold |

## Columns Intentionally Excluded from the Gold Layer
`Customer_Email`, `Customer_Password`, `Customer_Fname`, `Customer_Lname`, `Customer_Street`, `Product_Image` — PII or cosmetic fields with no analytical value for this project's KPI pillars.

## Known Data Characteristics (see `docs/data_quality_report.md` for full detail)
- `Late_delivery_risk` disagrees materially with the actual `Days_for_shipping_real` vs `Days_for_shipment_scheduled` outcome — not used for KPIs.
- `Sales` does not always reconcile to `Product_Price × Quantity × (1 - Discount_Rate)` — trusted as-reported.
- Negative `Order_Item_Quantity`/`Sales` values represent returns/cancellations, not data errors — flagged via `is_return_or_cancellation`, not deleted.
- `First Class` shipping mode carries a near-100% late-delivery rate due to a structurally short scheduled window, not a data defect.
