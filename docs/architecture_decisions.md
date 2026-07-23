# Architecture Decision Records (ADRs)


## ADR-001: Medallion Architecture (Bronze / Silver / Gold)
**Decision:** Separate raw, cleaned, and business-ready data into distinct schemas (`bronze`, `silver`, `gold`) rather than transforming in place.
**Reason:** Preserves full data lineage and auditability — any number can be traced back to an untouched copy of the source file. This is the modern data warehouse standard (used by Databricks, Snowflake, and most contemporary data teams).

## ADR-002: All Bronze Columns Typed as TEXT
**Decision:** Every column in `bronze.orders_raw` is loaded as `TEXT`, regardless of its apparent type.
**Reason:** Raw source files are often dirty. Forcing strict types (`INT`, `DATE`) at import time means a single malformed row fails the entire load. Type casting is deferred to Silver, where it's done defensively (regex-guarded `CASE WHEN` casts) so bad values become explicit `NULL`s rather than crashing the pipeline.

## ADR-003: Star Schema over a Flat Table
**Decision:** Model the Gold layer as one fact table (`fact_order_items`) plus five dimension tables, rather than a single wide table.
**Reason:** Matches the Kimball dimensional modeling standard, improves query/aggregation performance, reduces storage by not repeating descriptive text on every row, and aligns with how Power BI's VertiPaq engine is optimized to work.

## ADR-004: Order-Item Grain for the Fact Table
**Decision:** `fact_order_items` grain = one row per product line item within one order (not one row per order).
**Reason:** This matches the natural grain of the source data. Every KPI in the project is built with this explicitly in mind — e.g., `COUNT(DISTINCT order_id)` for order counts vs `COUNT(*)`/`COUNTROWS()` for line-item counts, and OTIF is computed via an order-level collapse (SQL CTE / DAX `SUMMARIZE`) rather than a direct fact-table aggregation.

## ADR-005: Negative Quantity/Sales Flagged, Not Deleted
**Decision:** Rows with negative `Order_Item_Quantity` or `Sales` are kept and flagged via `is_return_or_cancellation`, not removed.
**Reason:** These values represent real returns/cancellations, not data errors. Deleting them would silently understate return-rate metrics and lose real business signal. Flagging preserves completeness while making it trivial for any KPI query to filter them in or out deliberately.

## ADR-006: `Late_delivery_risk` Excluded from All KPIs
**Decision:** Use an independently derived `is_late_delivery` field (`days_shipping_actual > days_shipping_scheduled`) instead of the source `Late_delivery_risk` column for every delivery-performance KPI.
**Reason:** Profiling showed `Late_delivery_risk` disagrees materially with actual shipping outcomes. It behaves like a pre-built ML label rather than a live outcome flag. Full investigation in `docs/data_quality_report.md`. `Late_delivery_risk` is retained as a reference attribute only.

## ADR-007: Sales Trusted As-Reported (Not Recomputed from Components)
**Decision:** Use the source `Sales` column directly rather than recalculating it as `Price × Quantity × (1 - Discount Rate)`.
**Reason:** Profiling found these don't always reconcile. Rather than silently overwrite reported revenue with a recomputed value, the as-reported figure is trusted, and the discrepancy is documented rather than hidden.

## ADR-008: Manually Built `dim_date` via `generate_series`
**Decision:** Construct a full, continuous calendar dimension in SQL rather than deriving dates only from what appears in the fact table.
**Reason:** Power BI's time-intelligence functions (`TOTALYTD`, `SAMEPERIODLASTYEAR`, etc.) require a gap-free date table to work correctly. A date dimension built only from fact-table dates would have gaps on days with zero orders, silently breaking these calculations.

## ADR-009: Role-Playing Date Dimension Handled Differently in SQL vs Power BI
**Decision:** In SQL, `dim_date` is joined twice (aliased) in the flat export view for `order_date` and `shipping_date`. In Power BI, only one relationship to `Dim Date` can be active; `Order Date` is set active by default, `Shipping Date` is inactive and invoked via `USERELATIONSHIP()` in specific DAX measures.
**Reason:** This is the correct, standard way to handle a role-playing dimension in each respective tool — SQL has no "active/inactive" relationship concept, while Power BI enforces exactly one active relationship per table pair.

## ADR-010: Import Mode over DirectQuery in Power BI
**Decision:** Power BI imports the Gold star schema tables rather than querying PostgreSQL live via DirectQuery.
**Reason:** The dataset (~180K fact rows plus small dimensions) comfortably fits in-memory. Import mode compresses data columnarly and makes DAX calculations significantly faster than DirectQuery's per-interaction live SQL queries. DirectQuery is reserved for very large or real-time datasets, which this is not.

## ADR-011: SQL KPI Views as Ground Truth, Not the Power BI Data Source
**Decision:** Power BI imports the raw star schema (fact + dimensions), not the pre-aggregated SQL KPI views from `sql/05_kpi_views.sql`. Those views instead serve as a validation reference for DAX measures.
**Reason:** DAX measures need to respond dynamically to whatever filters/slicers a user applies; a static SQL view is frozen at whatever grain it was aggregated to. Keeping the SQL views as an independent "source of truth" allows cross-validating that DAX measures compute the same numbers — a deliberate quality-assurance step, not redundant work.

## ADR-012: Sales Velocity as an Inventory Turnover Proxy
**Decision:** Use `units sold ÷ active selling days` as a substitute for true inventory turnover.
**Reason:** The source dataset contains no warehouse stock-on-hand data, making true inventory turnover (COGS ÷ average inventory) uncomputable. This proxy is clearly labeled as a substitute in both the KPI view and the dashboard, rather than presented as if it were the standard finance metric.

## ADR-013: Least-Privilege `bi_reader` Role for Power BI
**Decision:** Power BI connects to PostgreSQL using a dedicated read-only role (`bi_reader`) with `SELECT` access to the `gold` schema only — never an admin account, and never access to `bronze`/`silver`.
**Reason:** Standard data governance practice — the BI layer should never be able to modify data or see raw/staging layers, limiting blast radius if credentials are ever compromised.
