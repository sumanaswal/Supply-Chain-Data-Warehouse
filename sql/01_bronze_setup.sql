-- Create the database (run this once, outside a transaction)
CREATE DATABASE supply_chain_db;

-- Connect to supply_chain_db before running the below

-- Create schemas to physically separate our Medallion layers
CREATE SCHEMA bronze;   -- raw, untouched data
CREATE SCHEMA silver;   -- cleaned data
CREATE SCHEMA gold;     -- star schema / business layer

-- Creating raw table inside bronze schema
CREATE TABLE bronze.orders_raw (
    "Type"                          TEXT,
    "Days_for_shipping_real"        TEXT,
    "Days_for_shipment_scheduled"   TEXT,
    "Benefit_per_order"             TEXT,
    "Sales_per_customer"            TEXT,
    "Delivery_Status"               TEXT,
    "Late_delivery_risk"            TEXT,
    "Category_Id"                   TEXT,
    "Category_Name"                 TEXT,
    "Customer_City"                 TEXT,
    "Customer_Country"              TEXT,
    "Customer_Email"                TEXT,
    "Customer_Fname"                TEXT,
    "Customer_Id"                   TEXT,
    "Customer_Lname"                TEXT,
    "Customer_Password"             TEXT,
    "Customer_Segment"              TEXT,
    "Customer_State"                TEXT,
    "Customer_Street"               TEXT,
    "Customer_Zipcode"              TEXT,
    "Department_Id"                 TEXT,
    "Department_Name"               TEXT,
    "Latitude"                      TEXT,
    "Longitude"                     TEXT,
    "Market"                        TEXT,
    "Order_City"                    TEXT,
    "Order_Country"                 TEXT,
    "Order_Customer_Id"             TEXT,
    "order_date"                    TEXT,
    "Order_Id"                      TEXT,
    "Order_Item_Cardprod_Id"        TEXT,
    "Order_Item_Discount"           TEXT,
    "Order_Item_Discount_Rate"      TEXT,
    "Order_Item_Id"                 TEXT,
    "Order_Item_Product_Price"      TEXT,
    "Order_Item_Profit_Ratio"       TEXT,
    "Order_Item_Quantity"           TEXT,
    "Sales"                         TEXT,
    "Order_Item_Total"              TEXT,
    "Order_Profit_Per_Order"        TEXT,
    "Order_Region"                  TEXT,
    "Order_State"                   TEXT,
    "Order_Status"                  TEXT,
    "Order_Zipcode"                 TEXT,
    "Product_Card_Id"               TEXT,
    "Product_Category_Id"           TEXT,
    "Product_Description"           TEXT,
    "Product_Image"                 TEXT,
    "Product_Name"                  TEXT,
    "Product_Price"                 TEXT,
    "Product_Status"                TEXT,
    "shipping_date"                 TEXT,
    "Shipping_Mode"                 TEXT
);

-- Load raw data into table
COPY bronze.orders_raw
FROM 'C:\data\DataCoSupplyChainDataset.csv'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ',',
    ENCODING 'LATIN1',      -- fixes the UTF-8 byte sequence error
    QUOTE '"',
    NULL ''
);

-- Row count check: does it match the CSV row count (~180,519 rows)?
SELECT COUNT(*) FROM bronze.orders_raw;

-- Spot-check the first few rows
SELECT * FROM bronze.orders_raw LIMIT 5;

-- Check for any completely blank rows (import artifacts)
SELECT COUNT(*) FROM bronze.orders_raw WHERE "Order_Id" IS NULL;