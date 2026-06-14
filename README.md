# End-to-End Supply Chain Data Analytics & Modeling

## Project Overview
This project transforms a raw, 180,000+ row flat file (DataCo Supply Chain dataset) into a fully normalized, business-ready relational data warehouse. The objective was to engineer a robust data pipeline that cleanses dirty data, enforces chronological integrity, and models the data to uncover logistical bottlenecks and financial leakage.

## Tech Stack
* **Database:** PostgreSQL
* **Languages:** SQL (DDL, DML, TCL, Window Functions, CTEs)
* **Concepts:** Star Schema Design, ETL Pipelines, RFM Segmentation, Materialized Views
* **Visualization Ready:** Power BI / Tableau

## The Business Problem
The operations and fulfillment teams lacked visibility into their supply chain bottlenecks. Legacy flat-file systems allowed for dirty data (e.g., shipping dates occurring before order dates) and obscured key metrics like real-time profit margins and vendor SLA failures.

## The Solution & Architecture
I architected an end-to-end data pipeline to solve these operational blind spots:
1. **Data Modeling (DDL):** Designed a Star Schema (fact_orders, dim_customers, dim_products) with strict CHECK constraints to prevent time-travel anomalies and negative item quantities.
2. **Data Staging & ETL:** Ingested the raw CSV into a VARCHAR staging table to prevent pipeline crashes, then used SQL casting, string formatting (TRIM), and explicit time parsing (TO_TIMESTAMP) to cleanly load the production tables.
3. **Logistics & SLA Analysis:** Utilized OVER() Window Functions and Boolean aggregations to identify specific regions and shipping modes driving the highest late-delivery rates.
4. **Financial Auditing:** Leveraged Common Table Expressions (CTEs) to calculate net profit margins and isolate customer segments overly reliant on discounts.
5. **RFM Customer Segmentation:** Deployed the NTILE() window function to mathematically score and categorize the customer base into actionable marketing tiers (e.g., "Champions", "At Risk").
6. **BI Deployment:** Created indexed MATERIALIZED VIEWS to provide a clean, read-only analytical layer, preventing heavy dashboard queries from locking the transactional database.

## Key Insights Discovered
* Standard Class' shipping was responsible for over 60% of all late delivery risks, significantly disproportionate to its overall order volume.
* By deploying an automated RFM scoring model, I found that less than 15% of the customer base qualified as 'Champions (VIPs)', yet they generated nearly 40% of the total net revenue.
* I identified a severe margin erosion in specific product categories. While top-line gross revenue was high, over-reliance on aggressive discount rates (averaging >15% in certain regions) dragged the net profit margin down to unsustainable levels.

## How to Run This Project
1. Clone this repository.
2. Download the raw DataCo dataset from Kaggle.
3. Execute the SQL scripts in numerical order (01 through 08) in your PostgreSQL environment.
