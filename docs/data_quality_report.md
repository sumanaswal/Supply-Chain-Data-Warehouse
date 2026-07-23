# Data Quality Report

This report summarizes the profiling performed on the Bronze (raw) layer across 5 standard data quality dimensions — **Completeness, Uniqueness, Validity, Consistency, Accuracy** — before any cleaning was applied. Full queries live in `sql/02_data_profiling.sql`; results are logged in the queryable `bronze.data_profiling_log` table.

---

## Summary of Findings

| Category | Check | Finding | Decision |
|---|---|---|---|
| Completeness | Null zipcodes (`Order_Zipcode`, `Customer_Zipcode`) | Minor gaps present | Left `NULL` in Silver — not used in any KPI; imputing would fabricate data |
| Completeness | Null `order_date` / `shipping_date` | Small number of rows | Isolated into `silver.orders_excluded_no_dates`, removed from main analytical table — unusable for time-based KPIs |
| Uniqueness | `Order_Item_Id` duplicates | Confirmed as valid grain/primary key candidate | Deduplicated via `DISTINCT ON` / `ROW_NUMBER()` in Silver |
| Uniqueness | Full-row duplicates | No material duplication found | No action needed |
| Validity | Non-numeric `Sales` / `Order_Item_Quantity` | Values conform to expected numeric pattern | Safe (regex-guarded) cast applied in Silver |
| Validity | Negative `Sales` / `Order_Item_Quantity` | Present in the data | **Not deleted** — flagged via `is_return_or_cancellation`, since these represent returns/cancellations, a real business signal |
| Consistency | Categorical variants (`Delivery_Status`, `Shipping_Mode`, `Order_Status`) | Casing/whitespace inconsistencies found | Standardized via `TRIM` + `INITCAP`/`UPPER` in Silver |
| Consistency | `Order_Status` includes `SUSPECTED_FRAUD` | Not an error — genuine business category | Retained as a valid status value |
| Accuracy | `Sales` vs `Price × Qty × (1 - Discount)` | Material mismatch found | `Sales` trusted as-reported rather than recomputed from components |
| Accuracy | `Late_delivery_risk` vs actual outcome | **Material mismatch — investigated in depth below** | Derived `is_late_delivery` field used as sole KPI source of truth |

---

## Deep-Dive Investigation: `Late_delivery_risk`

### The finding
Initial KPI queries showed many orders that were demonstrably delivered late (`Days_for_shipping_real > Days_for_shipment_scheduled`) but carried `Late_delivery_risk = 0`.

### Step 1 — Understand what the column actually is
`Late_delivery_risk` is not a live recalculation of "was this order late." It behaves like a **pre-built label**, likely originally created as a target variable for a machine learning classification exercise on this dataset — distinct from the ground-truth day-count fields (`Days_for_shipping_real`, `Days_for_shipment_scheduled`) and the categorical `Delivery_Status` field.

### Step 2 — Quantify the mismatch
```sql
SELECT
    COUNT(*) AS total_valid_rows,
    SUM(CASE WHEN "Late_delivery_risk"::INT = 0
              AND "Days_for_shipping_real"::INT > "Days_for_shipment_scheduled"::INT
             THEN 1 ELSE 0 END) AS risk_0_but_actually_late,
    ROUND(
        100.0 * SUM(CASE WHEN "Late_delivery_risk"::INT = 0
                          AND "Days_for_shipping_real"::INT > "Days_for_shipment_scheduled"::INT
                         THEN 1 ELSE 0 END) / COUNT(*), 2
    ) AS pct_mismatch
FROM bronze.orders_raw
WHERE "Days_for_shipping_real" ~ '^\d+$'
  AND "Days_for_shipment_scheduled" ~ '^\d+$'
  AND "Late_delivery_risk" ~ '^\d+$';
```
Result: a material percentage of rows show `Late_delivery_risk = 0` despite the order actually running late by day-count — confirming this is not a rounding quirk but a systemic disagreement.

### Step 3 — Cross-check against the other ground-truth field
`Delivery_Status = 'Late delivery'` was confirmed to align closely with the day-count-derived "Actually Late" outcome, since both are built from the same real shipping-day comparison — establishing `Delivery_Status` and the raw day-counts as the trustworthy ground truth, and `Late_delivery_risk` as the outlier.

### Step 4 — Follow-up: First Class shipping mode near-100% late rate
A related investigation arose when the Region × Shipping Mode late-delivery matrix showed **First Class at ~100% late across every single region**. Rather than assume a DAX/model bug, this was verified directly in SQL:
```sql
SELECT g.order_region, s.shipping_mode, COUNT(*) AS total_order_items,
       SUM(CASE WHEN is_late_delivery THEN 1 ELSE 0 END) AS total_late_orders,
       ROUND(SUM(CASE WHEN is_late_delivery THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS late_delivery_rate_pct
FROM gold.fact_order_items f
JOIN gold.dim_geography g ON f.geography_key = g.geography_key
JOIN gold.dim_shipping_mode s ON s.shipping_mode_key = f.shipping_mode_key
WHERE f.is_return_or_cancellation = FALSE AND s.shipping_mode = 'First Class'
GROUP BY g.order_region, s.shipping_mode
ORDER BY g.order_region;
```
The SQL result matched the dashboard — confirming this is a **genuine data characteristic, not a bug**. Each shipping mode in this dataset has a fixed, mode-specific `days_shipping_scheduled` value; First Class's scheduled window is short enough that real fulfillment operations essentially never meet it, producing a ~100% late rate by definition across the entire dataset.

**Confirmed in the final Power BI build:** the completed dashboard shows First Class at exactly **100.00%** late delivery across every region in the Region × Shipping Mode matrix, with an overall project OTIF Rate of **40.83%** and Late Delivery Rate of **57.29%** — both consistent with a dataset where one entire shipping mode is structurally non-compliant with its own SLA. A related, non-obvious finding surfaced once real numbers were in: **First Class also has the highest profit margin of any shipping mode (12.61%)**, meaning this is not a "low-value, unreliable mode" story — it's a high-value mode that is being actively let down by an unrealistic promised delivery window. See `docs/recommendations.md` for how this changes the recommended fix.

### Decision (documented, not silent)
> For all late-delivery KPIs (OTIF, Late Delivery %, on-time performance by region/shipping mode), this project uses the derived field `is_late_delivery` (built from `days_shipping_actual > days_shipping_scheduled`) as the single source of truth. `Late_delivery_risk` is retained in the Silver/Gold layer as a reference attribute only (useful for a potential future predictive-modeling extension) but is **excluded from every dashboard KPI**, since it was shown to disagree materially with actual outcomes. Separately, First Class's near-100% late rate is retained and reported as-is — it reflects a real, structurally unachievable SLA promise rather than a data defect, and is one of this project's core business findings rather than something to "fix."

---
