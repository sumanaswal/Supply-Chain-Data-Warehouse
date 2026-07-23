# Recommendations

Findings describe what happened. Recommendations describe what should change. This document connects every finding from the actual, built dashboard (`supply_chain_dashboard.pdf`) to a specific, prioritized, measurable recommendation.

**Revision note:** An earlier draft of this document, written before the dashboard was built with real data, assumed First Class was both the least reliable *and* least profitable shipping mode. The real data shows the opposite on margin — First Class is the least reliable mode but the *most* profitable (12.61% margin). That recommendation has been corrected below; it is a materially different business problem than originally assumed, which is itself worth noting: **illustrative/placeholder numbers should never be treated as findings until validated against the real build.**

Each entry follows the same structure: **Finding → Recommendation → Why this priority → How to validate impact.**

---

## 1. Fix the First Class SLA — but do not reduce First Class volume

**Finding:** First Class shows a ~100% late-delivery rate across every region (Delivery Performance page), traced to a scheduled delivery window that real fulfillment operations essentially never meet. At the same time, First Class carries the **highest profit margin of any shipping mode (12.61%)** — higher than Standard (11.98%), Second Class (11.69%), and Same Day (11.63%).

**Recommendation:** This is a capacity/operations problem, not a pricing or routing-away problem. Invest in the fulfillment capacity, carrier relationships, or warehouse proximity needed to actually hit the First Class promised window — because unlike a low-margin unreliable mode, First Class is worth fixing rather than de-emphasizing. Do **not** apply the "shift volume away" logic that would make sense for a low-margin mode.

**Why this priority (High):** A mode that is both high-margin and consistently broken represents the largest addressable upside on this entire dashboard — fixing it protects revenue that's already profitable, rather than needing to build profitability from scratch elsewhere.

**How to validate impact:** Track `Avg Shipping Delay (Days)` for First Class specifically (currently 1.0 day average) alongside `Profit Margin %` — delay should fall toward zero without margin falling, confirming the fix didn't require discounting or rerouting to achieve.

---

## 2. Investigate Second Class specifically — it underperforms its position

**Finding:** Second Class has the **second-worst late-delivery rate (79.83%)** and the **highest average shipping delay of any mode (2.0 days)** — worse than Same Day (47.93% late, 0.5-day delay) despite Same Day being marketed as the faster/more urgent option.

**Recommendation:** This pattern doesn't fit a simple "faster promised modes are less reliable" story — Second Class is a mid-tier option performing worse than a faster one. Investigate whether Second Class shipments are being deprioritized operationally (e.g., carrier capacity allocated to Same Day and Standard first, leaving Second Class shipments to slip) or whether its scheduled window has the same structural mismatch identified for First Class.

**Why this priority (High):** This is a genuinely counterintuitive finding that a surface-level read of the dashboard could miss (most viewers would assume First Class and Same Day are the problem children) — worth flagging explicitly so it doesn't get deprioritized by assumption.

**How to validate impact:** Re-run `gold.vw_delivery_performance` filtered to Second Class after any process change; both `late_delivery_rate_pct` and `avg_shipping_delay_days` should drop.

---

## 3. Prioritize root-cause reviews in Western Europe and Central America

**Finding:** Western Europe has the highest late-delivery rate among high-volume regions (58.53%, 10,010 orders), with Central America close behind (57.11%, 9,396 orders) — the two largest regions by order volume also carry the two highest late-delivery rates in the Regional Performance Summary.

**Recommendation:** Investigate carrier partnerships, warehouse/distribution proximity, and customs/border handling specific to these two regions before addressing smaller regions with similar rates but far less order volume.

**Why this priority (High):** Prioritizing by "rate × volume" rather than rate alone ensures the fix with the largest total business impact happens first.

**How to validate impact:** Re-run `gold.vw_regional_performance` filtered to Western Europe and Central America after any operational change; watch both `late_delivery_rate_pct` and `avg_lead_time_days`.

---

## 4. Do not pursue segment-specific delivery fixes

**Finding:** Late delivery rate is nearly flat across Home Office (57.59%), Consumer (57.31%), and Corporate (57.08%) segments.

**Recommendation:** Since the delivery problem is not customer-type-driven, avoid initiatives like "improve the Corporate delivery experience" — they would spend resources without addressing the actual (mode/regional/operational) root cause identified in Recommendations 1–3.

**Why this priority (Medium):** This is a "stop doing" recommendation rather than a "start doing" one — its value is in preventing wasted effort.

**How to validate impact:** Confirm segment variance in late-delivery rate remains low after mode/regional fixes are applied.

---

## 5. Review discount policy for Computers specifically

**Finding:** On the discount-vs-margin scatter (Cost & Margin page), most categories cluster tightly between 10.14%–10.20% discount and 11.5%–12.6% margin. Computers is a clear outlier — the highest discount (~10.22%) and lowest margin (~11%) of any category shown.

**Recommendation:** Audit current discount thresholds/promotional cadence for Computers specifically, since it doesn't follow the pattern of the rest of the portfolio. Given how tightly other categories cluster, this looks like an isolated policy or promotional issue rather than a portfolio-wide discounting problem.

**Why this priority (Medium):** A single-category issue is lower urgency than the delivery-reliability findings above, but is a clean, well-defined fix once identified.

**How to validate impact:** Re-plot the discount-vs-margin scatter after a policy change; Computers should move toward the cluster of other categories.

---

## 6. Shift volume toward Standard Class where SLA allows

**Finding:** Standard Class is the most reliable shipping mode (39.77% late — the lowest of any mode) and holds a solid margin (11.98%), while carrying the largest share of order volume already (39K orders, 59.81% of total).

**Recommendation:** Where customer SLA requirements permit, continue favoring Standard Class as the default; use it as the benchmark for what "working" looks like when evaluating fixes to the other three modes.

**Why this priority (Medium):** This is largely already happening (it has the largest volume share) — the recommendation here is to protect and reinforce this pattern rather than build something new.

**How to validate impact:** Monitor Standard Class's share of total order volume and confirm its reliability/margin profile doesn't degrade as volume grows.

---

## 7. Treat Fishing and Cleats as two different category strategies

**Finding:** Fishing is the top category by total sales ($6.2M, 18.84% share) but has one of the lowest sales-velocity rates among the top 5 categories (~15–17 units/day) — indicating fewer, higher-value transactions. Cleats ranks second in total sales ($4.0M) but has by far the highest velocity (~70 units/day) — indicating many smaller, more frequent transactions.

**Recommendation:** Don't apply the same commercial strategy to both. For Fishing (high-value, low-frequency), focus on protecting average order value and margin per transaction. For Cleats (high-frequency, high-volume), focus on protecting per-unit margin, since its volume means even a small per-unit discount or cost increase compounds into a large total dollar impact.

**Why this priority (Medium):** This is a strategic insight rather than an active problem — valuable for planning, but not as time-sensitive as the delivery-reliability findings.

**How to validate impact:** Track `sales_velocity_units_per_day` and `Profit Margin %` for each category independently; a successful strategy should show stable or improving margin for Cleats and stable or improving average order value for Fishing.

---

## Summary — Recommended Sequencing

1. **Immediate (High priority, do in parallel):** Fix First Class fulfillment capacity/SLA without reducing its volume (#1); investigate Second Class's unexpectedly poor performance (#2); begin Western Europe and Central America root-cause reviews (#3).
2. **Near-term (Medium):** Reinforce Standard Class as the default where SLA allows (#6); apply category-specific strategies to Fishing vs Cleats (#7).
3. **Lower urgency but well-defined (Medium):** Discount policy review for Computers (#5); explicitly deprioritize segment-specific delivery initiatives (#4).

