# DAX Measures Reference

This document reflects the **actual measure list exported from DAX Studio** (`$SYSTEM.MDSCHEMA_MEASURES`) against the built Power BI model — not an illustrative draft. All measures live in a dedicated disconnected `_Measures` table, keeping the Fields pane organized and enforcing the rule that every number on the dashboard comes from a named measure, never a raw-column aggregation.

---

## Foundational Measures

```dax
Total Sales = SUM(fact_order_items[net_sales])
Total Profit = SUM(fact_order_items[profit_per_order])
Total Order Items = COUNTROWS(fact_order_items)
Total Orders = DISTINCTCOUNT(fact_order_items[order_id])
Total Units Sold = SUM(fact_order_items[order_quantity])
Total Customers = DISTINCTCOUNT(fact_order_items[customer_key])
Total Countries = DISTINCTCOUNT(dim_geography[order_country])
Total Markets = DISTINCTCOUNT(dim_geography[market])
Total Departments = DISTINCTCOUNT(dim_product[department_id])
Active Categories = DISTINCTCOUNT(dim_product[category_id])

Profit Margin % = DIVIDE([Total Profit], [Total Sales], 0)

Avg Lead Time (Days) = AVERAGE(fact_order_items[days_shipping_actual])
Avg Shipping Delay (Days) = AVERAGE(fact_order_items[shipping_delay_days])
AVG Discount % = AVERAGE(fact_order_items[discount_rate])

Avg Revenue Per Unit =
    DIVIDE([Total Sales], [Total Units Sold], 0)
```

**Note on `Total Sales`:** this measure sums `fact_order_items[net_sales]`, not a generic `sales` column — the fact table in the final build carries **`gross_sales`, `net_sales`, and `discount_amount`** as three separate fields (used by the Waterfall measures below), rather than the single `sales` column specified in the original `04_gold_star_schema.sql`. See the schema note at the end of this document — the SQL DDL needs a small update to stay reproducible against this model.

`COUNTROWS(fact_order_items)` (line-item count) vs `DISTINCTCOUNT(fact_order_items[order_id])` (distinct order count) are kept as two separate base measures — the single most important grain distinction in this project, since the fact table's grain is one row per order line item.

---

## Delivery Performance

```dax
Late Order Items =
    CALCULATE(
        [Total Order Items],
        fact_order_items[is_late_delivery] = TRUE,
        fact_order_items[is_return_or_cancellation] = FALSE
    )

Late Delivery Rate % =
    DIVIDE(
        [Late Order Items],
        CALCULATE(
            [Total Order Items],
            fact_order_items[is_return_or_cancellation] = FALSE
        ),
        0
    )

On-Time Delivery Rate % = 1 - [Late Delivery Rate %]

Late Delivery Rate % (by Shipping Date) =
CALCULATE(
    [Late Delivery Rate %],
    -- using the inactive relationship between fact_order_items[shipping_date_key] and dim_date[date_key]
    USERELATIONSHIP(fact_order_items[shipping_date_key], dim_date[date_key])
)
```

Numerator and denominator both exclude `is_return_or_cancellation = TRUE`, keeping the filter logic consistent on both sides — a mismatched denominator here is the single most common way this kind of ratio measure silently produces a wrong percentage. `Late Delivery Rate % (by Shipping Date)` uses `USERELATIONSHIP` to temporarily activate the shipping-date relationship (inactive by default, since `Dim Date` plays two roles in this model) without disturbing every other measure's default order-date behavior.

---

## OTIF (order-level grain, collapsed from line-item grain)

```dax
OTIF Orders =
VAR OrderLevelTable =
    ADDCOLUMNS(
        SUMMARIZE(fact_order_items, fact_order_items[order_id]),
        "HasLateItem",
            CALCULATE(MAX(fact_order_items[shipping_delay_days]) > 0),
        "HasCancelledItem",
            CALCULATE(
                MAXX(
                    fact_order_items,
                    IF(fact_order_items[is_return_or_cancellation], 1, 0)
                )
            )
    )
RETURN
    COUNTROWS(
        FILTER(
            OrderLevelTable,
            [HasLateItem] = FALSE && [HasCancelledItem] = 0
        )
    )

OTIF Rate % =
    DIVIDE([OTIF Orders], [Total Orders], 0)
```

`SUMMARIZE` + `ADDCOLUMNS` collapses the fact table to one virtual row per `order_id`, computing "did any line item in this order ship late" and "was any line item a return/cancellation" as row-context flags, before filtering down to genuinely OTIF orders. Note the built model uses `MAXX(fact_order_items, IF(...))` for the cancellation flag rather than a plain `MAX()` over a boolean — a slightly more explicit but functionally equivalent approach to the same logic gate.

---

## Time Intelligence — YoY Pattern

The model applies one consistent, reusable pattern for every YoY measure: compute the prior-year value via `SAMEPERIODLASTYEAR`, then `DIVIDE` the change over the prior-year base.

```dax
Sales PY (Prior Year) =
    CALCULATE([Total Sales], SAMEPERIODLASTYEAR(dim_date[full_date]))

Sales YoY Growth % =
    DIVIDE([Total Sales] - [Sales PY (Prior Year)], [Sales PY (Prior Year)], 0)

Sales YTD = TOTALYTD([Total Sales], dim_date[full_date])
Sales MTD = TOTALMTD([Total Sales], dim_date[full_date])

Orders PY (Prior Year) =
    CALCULATE([Total Orders], SAMEPERIODLASTYEAR(dim_date[full_date]))

Orders YoY Growth % =
    DIVIDE([Total Orders] - [Orders PY (Prior Year)], [Orders PY (Prior Year)], 0)
```

The same `VAR <metric>PriorYear = CALCULATE([Base Measure], SAMEPERIODLASTYEAR(dim_date[full_date])) RETURN DIVIDE([Base Measure] - <metric>PriorYear, <metric>PriorYear, 0)` template is repeated for every KPI card's YoY badge:

| YoY Measure | Base Measure |
|---|---|
| `Avg Discount YoY %` | `AVG Discount %` |
| `Avg Revenue Per Unit YoY %` | `Avg Revenue Per Unit` |
| `Avg Shipping Delay Days YoY %` | `Avg Shipping Delay (Days)` |
| `Late Delivery Rate YoY %` | `Late Delivery Rate %` |
| `On Time Delivery Rate YoY %` | `On-Time Delivery Rate %` |
| `OTIF Rate YoY %` | `OTIF Rate %` |
| `Profit Margin YoY %` | `Profit Margin %` |
| `Return Rate YoY %` | `Return Rate %` |
| `Total Profit YoY %` | `Total Profit` |
| `Total Units Sold YoY %` | `Total Units Sold` |

Only `Total Sales` and `Total Orders` are given explicit named `PY (Prior Year)` variables as separate measures (used elsewhere on their own, e.g. potentially for a variance chart); the rest compute the prior-year value inline inside a `VAR` local to their own YoY measure. This works correctly for every KPI card on all 5 dashboard pages **only because `dim_date` is a continuous, gap-free calendar marked as an official Date Table** — confirming the Step 8 modeling decision was necessary, not just good practice.

---

## Cost, Margin & Waterfall

```dax
Gross Sales = SUM(fact_order_items[gross_sales])
Discount Impact = SUM(fact_order_items[discount_amount]) * -1

Waterfall Values =
SWITCH(
    SELECTEDVALUE('WaterfallCategories'[Category]),
    "Gross Sales", [Gross Sales],
    "Discounts", [Discount Impact],
    BLANK()
)

Return/Cancellation Count =
    CALCULATE([Total Order Items], fact_order_items[is_return_or_cancellation] = TRUE())

Return Rate % =
    DIVIDE([Return/Cancellation Count], [Total Order Items], 0)
```

`Waterfall Values` is driven by a small **disconnected table** `WaterfallCategories` (columns: `Category` = `{"Gross Sales", "Discounts"}`), exactly the pattern recommended in Step 10 — Power BI's native Waterfall visual expects a category column with signed values, so this measure routes to the correct underlying number depending on which category label is currently in context. `Discount Impact` is negated (`* -1`) so it renders as a decrease in the waterfall rather than requiring a separate signed-value column upstream.

---

## Category, Segment & Regional Benchmarking

```dax
Top Category Share =
    DIVIDE(
        MAXX(ALL(dim_product[category_name]), [Total Sales]),
        CALCULATE([Total Sales], ALL(fact_order_items)),
        0
    )

Top Category Share (Name) =
VAR T = TOPN(1, ALL(dim_product[category_name]), [Total Sales], DESC)
RETURN MAXX(T, dim_product[category_name])

Segment Share % =
    DIVIDE(
        [Total Customers],
        CALCULATE([Total Customers], REMOVEFILTERS(dim_customer[customer_segment])),
        0
    )

Top Segment Share % =
    MAXX(VALUES(dim_customer[customer_segment]), CALCULATE([Segment Share %]))

Top Segment Share (Name) =
VAR T = TOPN(1, ALL(dim_customer[customer_segment]), [Segment Share %], DESC)
RETURN MAXX(T, dim_customer[customer_segment])

Sales Rank by Region =
RANKX(ALL(dim_geography[order_region]), [Total Sales], , DESC)

Weakest Region OTIF =
    MINX(ALL(dim_geography[order_region]), [OTIF Rate %])

Weakest Region OTIF (Name) =
VAR T = TOPN(1, ALL(dim_geography[order_region]), [OTIF Rate %], ASC)
RETURN MINX(T, dim_geography[order_region])
```

Two techniques worth highlighting:
- **`Segment Share %`** uses `REMOVEFILTERS(dim_customer[customer_segment])` rather than `ALL()` on the whole table — this clears only the segment filter while preserving any other active filters (year, market, etc.), so the "% of total customers" denominator still respects the rest of the report's slicers. This is a more precise, deliberate choice than a blanket `ALL()`.
- **`Weakest Region OTIF` / `Top Category Share` / `Top Segment Share`** all follow the same "iterate over `ALL()` of a dimension column, evaluate a measure per value, then `MINX`/`MAXX`/`TOPN` to find the extreme" pattern — this is the standard DAX idiom for "best/worst X by Y" KPI cards, and it appears three times in this model applied to three different business questions (weakest region, top category, top segment).

---

## Sales Velocity

```dax
Velocity =
    DIVIDE(
        CALCULATE([Total Units Sold], fact_order_items[is_return_or_cancellation] = FALSE()),
        CALCULATE(
            DISTINCTCOUNT(fact_order_items[order_date_key]),
            fact_order_items[is_return_or_cancellation] = FALSE()
        ),
        0
    )

AVG Sales Velocity =
VAR Top5 =
    TOPN(
        5,
        ADDCOLUMNS(ALL(dim_product[category_name]), "@velocity", [Velocity]),
        [@velocity],
        DESC
    )
RETURN
    FORMAT(AVERAGEX(Top5, [@Velocity]), "0.00") & " Units/Day"

Slowest AVG Sales Velocity =
VAR Top1 =
    TOPN(
        1,
        ADDCOLUMNS(ALL(dim_product[category_name]), "@velocity", [Velocity]),
        [@velocity],
        ASC
    )
RETURN
    FORMAT(AVERAGEX(Top1, [@Velocity]), "0.00") & " Units/Day"

Slowest AVG Sales Velocity (Name) =
VAR Top1 =
    TOPN(
        1,
        ADDCOLUMNS(ALL(dim_product[category_name]), "@velocity", [Velocity]),
        [@velocity],
        ASC
    )
RETURN
    MAXX(Top1, dim_product[category_name])
```

**Improvement over the original SQL-side design:** the SQL view (`gold.vw_product_velocity`) used `COUNT(DISTINCT d.full_date)` against the full calendar joined in, while this DAX measure uses `DISTINCTCOUNT(fact_order_items[order_date_key])` — counting only dates that actually appear in the fact table for the current filter context, rather than every calendar day in range. This is a subtly more correct denominator for "active selling days," since a category with no fact rows on a given day shouldn't be diluting its velocity by that empty day. Worth reconciling this difference explicitly if cross-validating `AVG Sales Velocity` against the SQL view, rather than expecting an exact match.

`AVG Sales Velocity` and `Slowest AVG Sales Velocity` both return a **formatted text string** (`FORMAT(..., "0.00") & " Units/Day"`) rather than a raw number — a deliberate choice for a KPI card that needs to display units inline, though it means these two measures can't be used inside further numeric calculations or conditional formatting without re-parsing the text.

---

## Housekeeping

```dax
blank = BLANK()
```

A common Power BI trick: a measure that always returns `BLANK()`, used as a spacer/divider inside the `_Measures` table's field list for visual organization — not used on any visual directly.

---

## Validation Method

For a fixed period (e.g., Year = 2017, Month = 3), each core measure was placed on a table visual and compared against its corresponding row in the matching SQL view from `sql/05_kpi_views.sql`:

| DAX Measure | SQL View (ground truth) |
|---|---|
| `Late Delivery Rate %` | `gold.vw_delivery_performance.late_delivery_rate_pct` |
| `OTIF Rate %` | `gold.vw_otif.otif_rate_pct` / `gold.mv_otif` |
| `Profit Margin %` | `gold.vw_shipping_cost_efficiency.profit_margin_pct` |
| `Avg Lead Time (Days)` | `gold.vw_regional_performance.avg_lead_time_days` |

`AVG Sales Velocity` / `Slowest AVG Sales Velocity` are **not expected to match** `gold.vw_product_velocity` exactly, per the denominator difference noted above — this is a documented, intentional divergence, not a validation failure.

---

## Schema Note — Action Needed on the SQL Side

This model's `fact_order_items` table includes three sales-related columns not present in the original `sql/04_gold_star_schema.sql` DDL:

- `gross_sales`
- `net_sales`
- `discount_amount`

The original SQL script only defines a single `sales` column. To keep `sql/04_gold_star_schema.sql` reproducible against this actual Power BI model, it should be updated to populate these three fields (e.g., `gross_sales` = list price × quantity before discount, `discount_amount` = the dollar amount of discount applied, `net_sales` = the realized `Sales` figure from the source data) rather than the single `sales` column currently specified. Flagging this explicitly rather than leaving `README.md`'s "How to Reproduce" section silently broken for anyone who runs the SQL scripts and then opens this `.pbix`.
