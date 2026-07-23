SELECT 
	g.order_region,
	s.shipping_mode,
	COUNT(*) 							AS total_order_items,
	SUM(
		CASE WHEN is_late_delivery 
		THEN 1 ELSE 0 END) 				AS total_late_orders,
	ROUND(
		SUM(
			CASE WHEN is_late_delivery 
			THEN 1 ELSE 0 END) * 100.0 
			/ COUNT(*),2)  				AS late_delivery_rate_pct
FROM gold.fact_order_items f
JOIN gold.dim_geography g 		ON f.geography_key = g.geography_key
JOIN gold.dim_shipping_mode s 	ON s.shipping_mode_key = f.shipping_mode_key 
WHERE f.is_return_or_cancellation = FALSE 
	AND s.shipping_mode = 'First Class'
GROUP BY g.order_region, s.shipping_mode
ORDER BY g.order_region;

-----------------------------------------

SELECT 
    s.shipping_mode,
    f.days_shipping_scheduled,
    f.days_shipping_actual,
    COUNT(*) AS row_count
FROM gold.fact_order_items f
JOIN gold.dim_shipping_mode s ON f.shipping_mode_key = s.shipping_mode_key
WHERE s.shipping_mode = 'Second Class'
  AND f.is_return_or_cancellation = FALSE
GROUP BY s.shipping_mode, f.days_shipping_scheduled, f.days_shipping_actual
ORDER BY f.days_shipping_scheduled, f.days_shipping_actual;

-------------------------------------------
SELECT 
    s.shipping_mode,
    f.delivery_status,
    COUNT(*) AS row_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY s.shipping_mode), 2) AS pct_of_mode
FROM gold.fact_order_items f
JOIN gold.dim_shipping_mode s ON f.shipping_mode_key = s.shipping_mode_key
WHERE s.shipping_mode = 'Second Class'
  AND f.is_return_or_cancellation = FALSE
GROUP BY s.shipping_mode, f.delivery_status
ORDER BY row_count DESC;

SELECT 
    s.shipping_mode,
    MIN(f.days_shipping_scheduled) AS min_scheduled,
    MAX(f.days_shipping_scheduled) AS max_scheduled,
    ROUND(AVG(f.days_shipping_scheduled),2) AS avg_scheduled,
    ROUND(AVG(f.days_shipping_actual),2) AS avg_actual
FROM gold.fact_order_items f
JOIN gold.dim_shipping_mode s ON f.shipping_mode_key = s.shipping_mode_key
WHERE f.is_return_or_cancellation = FALSE
GROUP BY s.shipping_mode
ORDER BY avg_scheduled;

select * from gold.fact_order_items limit 10

SELECT 
	g.order_region,
	s.shipping_mode,
	COUNT(*) 							AS total_order_items,
	SUM(
		CASE WHEN is_late_delivery 
		THEN 1 ELSE 0 END) 				AS total_late_orders,
	ROUND(
		SUM(
			CASE WHEN is_late_delivery 
			THEN 1 ELSE 0 END) * 100.0 
			/ COUNT(*),2)  				AS late_delivery_rate_pct
FROM gold.fact_order_items f
JOIN gold.dim_geography g 		ON f.geography_key = g.geography_key
JOIN gold.dim_shipping_mode s 	ON s.shipping_mode_key = f.shipping_mode_key 
WHERE f.is_return_or_cancellation = FALSE 
	AND s.shipping_mode = 'Second Class'
GROUP BY g.order_region, s.shipping_mode
ORDER BY g.order_region;

---
SELECT 
FROM gold.fact_order_items f
JOIN gold.shipping_mode s ON f.shipping_mode_key = s.shipping_mode_key 