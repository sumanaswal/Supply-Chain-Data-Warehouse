# Global Supply Chain Performance Analytics

An end-to-end data analytics project covering the full pipeline from raw CSV to a governed SQL warehouse to a polished, insight-driven Power BI dashboard — built on the DataCo Smart Supply Chain dataset (Kaggle).

---

## Business Problem

Supply chain leadership needs visibility into order fulfillment performance, shipping delays, freight/margin efficiency, and product/regional performance — to identify bottlenecks and reduce late deliveries across markets. This project answers that need using a real dataset of ~180,000 order line items spanning 2015–2018, across 5 markets and 160+ countries.

---

## Key Findings

- **OTIF (On-Time-In-Full) Rate sits at 40.83%**, far below the 85% industry benchmark — barely 4 in 10 orders arrive both on-time and complete. Late Delivery Rate is 57.29%.
- **First Class shows a ~100% late-delivery rate across every single region.** This was investigated as a potential data/measure bug and confirmed instead to be a genuine data characteristic: a scheduled delivery window this mode essentially never meets, not a calculation error. Full investigation in [`docs/data_quality_report.md`](docs/data_quality_report.md).
- **First Class is simultaneously the least reliable AND the most profitable shipping mode** (12.61% margin — the highest of any mode). This is a more complex problem than "stop using it": First Class is unreliable but genuinely valuable to the business when it ships, so the fix is an SLA/capacity problem, not a routing-away problem.
- **Second Class is the second-least-reliable mode** (79.83% late, 2.0-day average delay) — worse than Same Day (47.93% late, 0.5-day delay). Standard Class is both the most reliable (39.77% late) and has a solid margin (11.98%).
- **Late delivery rate is nearly flat across all customer segments** (57.08–57.59%) — ruling out "customer type" as a driver and pointing instead to operational/regional causes.
- **Western Europe has the highest late-delivery rate among high-volume regions** (58.53%, 10,010 orders), with Central America close behind (57.11%, 9,396 orders) — both are "big enough to matter" priorities, distinct from smaller regions with similar rates but far less volume.
- **Fishing is the top category by sales** ($6.2M, 18.84% share) despite having one of the lowest sales-velocity rates among the top 5 categories (~15–17 units/day) — it sells in fewer, higher-value transactions. Cleats, by contrast, is the highest-velocity top category (~70 units/day) despite ranking second in total sales — a genuinely interesting volume-vs-value split worth highlighting.
- **Discount rates are tightly clustered (10.10%–10.22%) across shipping modes and most categories** — Computers is the one clear outlier, carrying both the highest discount and the lowest profit margin (~11%) among categories shown.
- **The `Late_delivery_risk` source column disagrees with actual shipping outcomes in a material share of rows** — confirmed to be a pre-built ML label rather than a live outcome flag. Decision: an independently derived `is_late_delivery` field (from real day-count comparisons) is used as the single source of truth for every delivery KPI in this project.

---

## Recommendations

Each recommendation below is tied directly to a specific finding above — not a generic best-practice statement — and includes how impact would be re-measured.

| # | Finding | Recommendation | Priority | How to validate impact |
|---|---|---|---|---|
| 1 | First Class has a ~100% late rate due to a structurally short scheduled SLA | Renegotiate the First Class promised delivery window to match realistic fulfillment capacity, or reposition it as a premium-priced option without a hard SLA guarantee | High | Re-measure `OTIF Rate %` for First Class 90 days after the SLA change |
| 2 | First Class is the least reliable mode but also the highest-margin mode (12.61%) | This is a capacity/SLA problem, not a pricing or routing-away problem — do not reduce First Class volume, since it's the most profitable mode; instead invest in the fulfillment capacity/carrier relationships needed to actually hit its promised window | High | Track `Avg Shipping Delay (Days)` for First Class alongside `Profit Margin %` — delay should fall without margin falling |
| 3 | Second Class is the second-least-reliable mode (79.83% late, 2.0-day avg delay) — worse than Same Day | Investigate Second Class specifically rather than assuming "faster modes are always worse"; its delay/reliability profile doesn't match its mid-tier positioning | High | Re-run `vw_delivery_performance` filtered to Second Class after any process change |
| 4 | Western Europe and Central America have the highest late rates among high-volume regions (58.53% and 57.11%) | Prioritize a carrier/fulfillment root-cause review in these two regions before smaller, lower-impact regions | High | Re-run `vw_regional_performance` filtered to both regions after intervention |
| 5 | Late delivery rate is flat across customer segments (57.08–57.59%) | Since the problem isn't customer-driven, avoid segment-specific fixes; concentrate resources on regional/carrier operations and the First/Second Class SLA issues instead | Medium | Confirm segment variance remains low post-fix (rules out a new segment-specific issue emerging) |
| 6 | Computers is a clear outlier — highest discount, lowest margin among categories shown | Review discount policy/thresholds specifically for Computers; other categories are tightly clustered and don't show the same pattern | Medium | Compare Computers' position on the discount-vs-margin scatter before/after policy change |
| 7 | Standard Class is both the most reliable mode (39.77% late) and holds a solid margin (11.98%) | Shift volume toward Standard Class where SLA allows, as a lower-risk lever than fixing First/Second Class reliability directly | Medium | Monitor overall `OTIF Rate %` as Standard Class's share of volume increases |
| 8 | Fishing is the top category by sales but has low sales velocity (~15–17 units/day); Cleats has the highest velocity (~70 units/day) despite ranking second in sales | Treat these as two different category strategies rather than one — Fishing is a high-value/low-frequency category (protect average order value), Cleats is a high-frequency/volume category (protect margin per unit, since volume amplifies small per-unit losses) | Medium | Track `sales_velocity_units_per_day` and `Profit Margin %` separately for each category type |

Full reasoning for each recommendation is in [`docs/recommendations.md`](docs/recommendations.md).

---

## Architecture

This project follows a **Medallion Architecture** (Bronze → Silver → Gold), the modern data warehouse standard used across the industry:

```
   RAW CSV (Kaggle)
        │
        ▼
 ┌─────────────┐     ┌──────────────┐     ┌────────────────┐
 │   BRONZE    │ ──▶ │    SILVER    │ ──▶ │      GOLD      │ ──▶ Power BI
 │ raw, as-is  │     │ cleaned,     │     │ Kimball star    │
 │ all TEXT    │     │ typed,       │     │ schema: fact +  │
 │ full        │     │ deduplicated,│     │ 5 dimensions,   │
 │ lineage     │     │ outlier-     │     │ KPI SQL views,  │
 │             │     │ flagged      │     │ indexed         │
 └─────────────┘     └──────────────┘     └────────────────┘
```

- **Bronze**: exact, untouched copy of the source CSV — every column as `TEXT`, for full auditability.
- **Silver**: defensive type-casting, deduplication (`ROW_NUMBER`/`DISTINCT ON`), categorical standardization, documented null-handling per column, outlier flags rather than deletions.
- **Gold**: a Kimball star schema — `fact_order_items` (grain: one order line item) joined to `dim_customer`, `dim_product`, `dim_geography`, `dim_shipping_mode`, and a manually built `dim_date` — plus a set of documented SQL KPI views used as validation ground truth for the BI layer.

**Grain statement:** one row in the fact table = one product line item within one order. Every KPI in this project is built with this grain explicitly in mind (e.g. `COUNT(DISTINCT order_id)` for order counts, vs `COUNT(*)` for line-item counts).

---

## Tech Stack

| Layer | Tool |
|---|---|
| Source data | Kaggle — DataCo Smart Supply Chain for Big Data Analysis (~180K rows) |
| Database | PostgreSQL |
| Data modeling | Kimball star schema (SQL DDL, surrogate keys, role-playing date dimension) |
| BI tool | Power BI Desktop (Import mode) |
| Semantic layer | DAX (grain-aware measures, `USERELATIONSHIP`, time intelligence) |

---

## Dashboard Preview

| Page | Focus |
|---|---|
| 1. Executive Summary | Top-line KPIs — Sales, Orders, OTIF, Late Delivery %, Profit Margin |
| 2. Delivery Performance | OTIF trend vs target, Region × Shipping Mode late-rate matrix, delay by mode |
| 3. Cost & Margin Analysis | Sales-to-profit waterfall, discount vs margin scatter by category, mode-level margin table |
| 4. Regional & Customer Deep-Dive | Sales by country map, segment breakdown, drill-through to order-level detail |
| 5. Product Performance | Category sales ranking, velocity trend, department/category treemap |

*(Screenshots: `images/page1_executive_summary.png` through `images/page5_product_performance.png`)*

---

## Data Quality & Methodology Notes

Every column in this dataset was profiled across 5 dimensions — completeness, uniqueness, validity, consistency, and accuracy — before any cleaning was performed. Findings are logged in a queryable SQL table (`bronze.data_profiling_log`) and summarized in [`docs/data_quality_report.md`](docs/data_quality_report.md).

The most significant finding: the source `Late_delivery_risk` column was cross-checked against actual shipping day-counts and the `Delivery_Status` categorical field, revealed to be an unreliable pre-built label, and was explicitly excluded from all KPI logic in favor of an independently derived field — a documented, defensible decision rather than a silent data-cleaning choice.

Architecture and modeling decisions (star schema vs flat table, Import vs DirectQuery, sales-velocity as an inventory-turnover proxy, etc.) are logged as lightweight ADRs in [`docs/architecture_decisions.md`](docs/architecture_decisions.md).

---

## How to Reproduce

1. Download the dataset from Kaggle: [DataCo Smart Supply Chain for Big Data Analysis](https://www.kaggle.com/datasets/shashwatwork/dataco-smart-supply-chain-for-big-data-analysis)
2. Create a PostgreSQL database (`supply_chain_db`) and run the SQL scripts in order:
   ```
   sql/01_bronze_setup.sql
   sql/02_data_profiling.sql
   sql/03_silver_cleaning.sql
   sql/04_gold_star_schema.sql
   sql/05_kpi_views.sql
   sql/06_permissions_indexing.sql
   ```
3. Open `powerbi/supply_chain_dashboard.pbix` in Power BI Desktop.
4. Update the data source connection to point to your local `supply_chain_db` instance and enter your credentials (a read-only `bi_reader` role is created in script 06).
5. Refresh the model.

---

## Skills Demonstrated

- Medallion architecture (Bronze/Silver/Gold) pipeline design with full data lineage and auditability
- Kimball dimensional modeling — surrogate keys, grain definition, role-playing date dimensions
- Defensive SQL — regex-guarded type casting, `NULLIF`/`DIVIDE` safe-division patterns, `ROW_NUMBER`/`DISTINCT ON` deduplication
- Systematic data quality profiling across 5 DQ dimensions, with documented (not silent) cleaning decisions
- DAX measure design — grain-aware aggregation, `USERELATIONSHIP` for role-playing dimensions, time intelligence
- Cross-validation discipline — SQL views used as ground truth to verify DAX measure correctness
- BI dashboard design — information hierarchy, disciplined color system, drill-through, conditional formatting as an alternative to redundant charts
- Translating findings into prioritized, measurable business recommendations rather than stopping at description

---

## Project Structure

```
supply-chain-analytics-project/
├── README.md
├── data/
│   ├── raw/                     (Kaggle CSV — see Kaggle link above)
│   └── data_dictionary.md
├── sql/
│   ├── 01_bronze_setup.sql
│   ├── 02_data_profiling.sql
│   ├── 03_silver_cleaning.sql
│   ├── 04_gold_star_schema.sql
│   ├── 05_kpi_views.sql
│   └── 06_permissions_indexing.sql
├── dax/
│   └── measures.md
├── powerbi/
│   └── supply_chain_dashboard.pbix
├── images/
│   ├── page1_executive_summary.png
│   ├── page2_delivery_performance.png
│   ├── page3_cost_margin.png
│   ├── page4_regional_customer.png
│   └── page5_product_performance.png
└── docs/
    ├── data_quality_report.md
    ├── architecture_decisions.md
    └── recommendations.md
```
