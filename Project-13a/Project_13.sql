CREATE WAREHOUSE P13_RETAIL_WH
WAREHOUSE_SIZE = 'XSMALL';
USE WAREHOUSE P13_RETAIL_WH;

CREATE DATABASE P13_RETAIL_SCHEMAS_DW;
USE DATABASE P13_RETAIL_SCHEMAS_DW;

CREATE SCHEMA P13_RETAIL_SCHEMAS_DW.SCHEMA_COMPARISON;
USE SCHEMA SCHEMA_COMPARISON;

CREATE or replace FILE FORMAT CSV_FORMAT
TYPE = 'CSV'
SKIP_HEADER = 1
FIELD_DELIMITER = ','
FIELD_OPTIONALLY_ENCLOSED_BY = '"';

CREATE OR REPLACE STAGE P13_RETAIL_STAGE
FILE_FORMAT = CSV_FORMAT;

LIST @P13_RETAIL_STAGE;
SHOW STAGES IN SCHEMA P13_RETAIL_SCHEMAS_DW.SCHEMA_COMPARISON;


--=============================================================================

CREATE TABLE STAR_DIM_STORE
(
    STORE_KEY           NUMBER AUTOINCREMENT PRIMARY KEY,
    STORE_ID            NUMBER,
    STORE_NAME          VARCHAR(100),
    CITY                VARCHAR(50),
    STATE               VARCHAR(50),
    REGION_NAME         VARCHAR(50),
    REGIONAL_MANAGER    VARCHAR(100)
);



CREATE TABLE STAR_DIM_PRODUCT
(
     PRODUCT_KEY        NUMBER AUTOINCREMENT PRIMARY KEY,
     PRODUCT_ID         NUMBER,
     PRODUCT_NAME       VARCHAR(100),
     SUBCATEGORY_NAME   VARCHAR(50),
     CATEGORY_NAME      VARCHAR(50),
     UNIT_PRICE         NUMBER(10,2)
);

CREATE OR REPLACE TABLE STAR_FACT_SALES
(
    SALES_KEY         NUMBER AUTOINCREMENT PRIMARY KEY,
    TRANSACTION_ID    VARCHAR(50),
    TRANSACTION_DATE  DATE,
    CUSTOMER_ID       NUMBER,
    STORE_KEY         NUMBER,
    PRODUCT_KEY       NUMBER,
    QUANTITY          NUMBER,
    TOTAL_AMOUNT      NUMBER(12,2),

    CONSTRAINT FK_STAR_STORE
        FOREIGN KEY (STORE_KEY)
        REFERENCES STAR_DIM_STORE(STORE_KEY),
    CONSTRAINT FK_STAR_PRODUCT
        FOREIGN KEY (PRODUCT_KEY)
        REFERENCES STAR_DIM_PRODUCT(PRODUCT_KEY)
);


INSERT INTO STAR_DIM_STORE
(
    STORE_ID,
    STORE_NAME,
    CITY,
    STATE,
    REGION_NAME,
    REGIONAL_MANAGER
)
SELECT
    $1,
    $2,
    $3,
    $4,
    $5,
    $6
FROM @P13_RETAIL_STAGE/regions_and_stores.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);


INSERT INTO STAR_DIM_PRODUCT
(
    PRODUCT_ID,
    PRODUCT_NAME,
    SUBCATEGORY_NAME,
    CATEGORY_NAME,
    UNIT_PRICE
)
SELECT
    $1,
    $2,
    $3,
    $4,
    $5,
FROM @P13_RETAIL_STAGE/product_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);

INSERT INTO STAR_FACT_SALES
(
    TRANSACTION_ID,
    TRANSACTION_DATE,
    CUSTOMER_ID,
    STORE_KEY,
    PRODUCT_KEY,
    QUANTITY,
    TOTAL_AMOUNT
)
SELECT
    S.$1,
    S.$2::DATE,
    S.$3,
    D.STORE_KEY,
    P.PRODUCT_KEY,
    S.$6,
    S.$6 * S.$7
FROM @P13_RETAIL_STAGE/sales_transactions.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) S
JOIN STAR_DIM_STORE D
    ON S.$4 = D.STORE_ID
JOIN STAR_DIM_PRODUCT P
    ON S.$5 = P.PRODUCT_ID;

--================TASK 6==========================================
CREATE TABLE SNOW_DIM_REGION
(
    REGION_KEY        NUMBER AUTOINCREMENT PRIMARY KEY,
    REGION_NAME       VARCHAR(50),
    REGIONAL_MANAGER  VARCHAR(100)
);
CREATE TABLE SNOW_DIM_STORE
(
    STORE_KEY    NUMBER AUTOINCREMENT PRIMARY KEY,
    STORE_ID     NUMBER,
    STORE_NAME   VARCHAR(100),
    CITY         VARCHAR(50),
    STATE        VARCHAR(50),
    REGION_KEY   NUMBER,

    CONSTRAINT FK_SNOW_STORE_REGION
        FOREIGN KEY (REGION_KEY)
        REFERENCES SNOW_DIM_REGION(REGION_KEY)
);

CREATE TABLE SNOW_DIM_CATEGORY
(
    CATEGORY_KEY   NUMBER AUTOINCREMENT PRIMARY KEY,
    CATEGORY_NAME  VARCHAR(50)
);


CREATE TABLE SNOW_DIM_SUBCATEGORY
(
    SUBCATEGORY_KEY   NUMBER AUTOINCREMENT PRIMARY KEY,
    SUBCATEGORY_NAME  VARCHAR(50),
    CATEGORY_KEY      NUMBER,

    CONSTRAINT FK_SNOW_SUBCATEGORY_CATEGORY
        FOREIGN KEY (CATEGORY_KEY)
        REFERENCES SNOW_DIM_CATEGORY(CATEGORY_KEY)
);


CREATE TABLE SNOW_DIM_PRODUCT
(
    PRODUCT_KEY       NUMBER AUTOINCREMENT PRIMARY KEY,
    PRODUCT_ID        NUMBER,
    PRODUCT_NAME      VARCHAR(100),
    UNIT_PRICE        NUMBER(10,2),
    SUBCATEGORY_KEY   NUMBER,

    CONSTRAINT FK_SNOW_PRODUCT_SUBCATEGORY
        FOREIGN KEY (SUBCATEGORY_KEY)
        REFERENCES SNOW_DIM_SUBCATEGORY(SUBCATEGORY_KEY)
);
--=============================================================================
-- TASK 8 — POPULATE SNOWFLAKE SCHEMA NORMALIZED DIMENSIONS
--=============================================================================


--=============================================================================
-- 8.1 LOAD REGION
--=============================================================================

INSERT INTO SNOW_DIM_REGION
(
    REGION_NAME,
    REGIONAL_MANAGER
)
SELECT DISTINCT
    $5,
    $6
FROM @P13_RETAIL_STAGE/regions_and_stores.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);


--=============================================================================
-- 8.2 LOAD STORE
--=============================================================================

INSERT INTO SNOW_DIM_STORE
(
    STORE_ID,
    STORE_NAME,
    CITY,
    STATE,
    REGION_KEY
)
SELECT
    S.$1,
    S.$2,
    S.$3,
    S.$4,
    R.REGION_KEY
FROM @P13_RETAIL_STAGE/regions_and_stores.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) S
JOIN SNOW_DIM_REGION R
    ON S.$5 = R.REGION_NAME;


--=============================================================================
-- 8.3 LOAD CATEGORY
--=============================================================================

INSERT INTO SNOW_DIM_CATEGORY
(
    CATEGORY_NAME
)
SELECT DISTINCT
    $4
FROM @P13_RETAIL_STAGE/product_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);


--=============================================================================
-- 8.4 LOAD SUBCATEGORY
--=============================================================================

INSERT INTO SNOW_DIM_SUBCATEGORY
(
    SUBCATEGORY_NAME,
    CATEGORY_KEY
)
SELECT
    P.$3,
    C.CATEGORY_KEY
FROM @P13_RETAIL_STAGE/product_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) P
JOIN SNOW_DIM_CATEGORY C
    ON P.$4 = C.CATEGORY_NAME;


--=============================================================================
-- 8.5 LOAD PRODUCT
--=============================================================================

INSERT INTO SNOW_DIM_PRODUCT
(
    PRODUCT_ID,
    PRODUCT_NAME,
    UNIT_PRICE,
    SUBCATEGORY_KEY
)
SELECT
    P.$1,
    P.$2,
    P.$5,
    S.SUBCATEGORY_KEY
FROM @P13_RETAIL_STAGE/product_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) P
JOIN SNOW_DIM_SUBCATEGORY S
    ON P.$3 = S.SUBCATEGORY_NAME;


--=============================================================================
-- OPTIONAL CHECK FOR TASK 8
--=============================================================================

SELECT * FROM SNOW_DIM_REGION;
SELECT * FROM SNOW_DIM_STORE;
SELECT * FROM SNOW_DIM_CATEGORY;
SELECT * FROM SNOW_DIM_SUBCATEGORY;
SELECT * FROM SNOW_DIM_PRODUCT;


--=============================================================================
-- TASK 9 — CREATE SNOWFLAKE SCHEMA FACT TABLE
--=============================================================================

CREATE TABLE SNOW_FACT_SALES
(
    SALES_KEY         NUMBER AUTOINCREMENT PRIMARY KEY,
    TRANSACTION_ID    VARCHAR(50),
    TRANSACTION_DATE  DATE,
    CUSTOMER_ID       NUMBER,
    STORE_KEY         NUMBER,
    PRODUCT_KEY       NUMBER,
    QUANTITY          NUMBER,
    TOTAL_AMOUNT      NUMBER(12,2),

    CONSTRAINT FK_SNOW_FACT_STORE
        FOREIGN KEY (STORE_KEY)
        REFERENCES SNOW_DIM_STORE(STORE_KEY),

    CONSTRAINT FK_SNOW_FACT_PRODUCT
        FOREIGN KEY (PRODUCT_KEY)
        REFERENCES SNOW_DIM_PRODUCT(PRODUCT_KEY)
);


--=============================================================================
-- TASK 9 — LOAD SNOWFLAKE FACT TABLE
--=============================================================================

INSERT INTO SNOW_FACT_SALES
(
    TRANSACTION_ID,
    TRANSACTION_DATE,
    CUSTOMER_ID,
    STORE_KEY,
    PRODUCT_KEY,
    QUANTITY,
    TOTAL_AMOUNT
)
SELECT
    S.$1,
    S.$2::DATE,
    S.$3,
    D.STORE_KEY,
    P.PRODUCT_KEY,
    S.$6,
    S.$6 * S.$7
FROM @P13_RETAIL_STAGE/sales_transactions.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) S
JOIN SNOW_DIM_STORE D
    ON S.$4 = D.STORE_ID
JOIN SNOW_DIM_PRODUCT P
    ON S.$5 = P.PRODUCT_ID;


--=============================================================================
-- TASK 10 — STAR SCHEMA ANALYTICS QUERY
-- TOTAL REVENUE BY REGION AND CATEGORY
--=============================================================================

SELECT
    D.REGION_NAME,
    P.CATEGORY_NAME,
    SUM(F.TOTAL_AMOUNT) AS TOTAL_REVENUE
FROM STAR_FACT_SALES F
JOIN STAR_DIM_STORE D
    ON F.STORE_KEY = D.STORE_KEY
JOIN STAR_DIM_PRODUCT P
    ON F.PRODUCT_KEY = P.PRODUCT_KEY
GROUP BY
    D.REGION_NAME,
    P.CATEGORY_NAME
ORDER BY
    D.REGION_NAME,
    P.CATEGORY_NAME;


--=============================================================================
-- TASK 11 — SNOWFLAKE SCHEMA ANALYTICS QUERY
-- TOTAL REVENUE BY REGION AND CATEGORY
--=============================================================================

SELECT
    R.REGION_NAME,
    C.CATEGORY_NAME,
    SUM(F.TOTAL_AMOUNT) AS TOTAL_REVENUE
FROM SNOW_FACT_SALES F

JOIN SNOW_DIM_STORE S
    ON F.STORE_KEY = S.STORE_KEY

JOIN SNOW_DIM_REGION R
    ON S.REGION_KEY = R.REGION_KEY

JOIN SNOW_DIM_PRODUCT P
    ON F.PRODUCT_KEY = P.PRODUCT_KEY

JOIN SNOW_DIM_SUBCATEGORY SC
    ON P.SUBCATEGORY_KEY = SC.SUBCATEGORY_KEY

JOIN SNOW_DIM_CATEGORY C
    ON SC.CATEGORY_KEY = C.CATEGORY_KEY

GROUP BY
    R.REGION_NAME,
    C.CATEGORY_NAME

ORDER BY
    R.REGION_NAME,
    C.CATEGORY_NAME;


--=============================================================================
-- TASK 12 — ARCHITECTURAL ANALYSIS
--=============================================================================

SELECT
    'Dimension Normalization Level' AS METRIC_FEATURE,
    'Denormalized (Flat)' AS STAR_SCHEMA,
    'Normalized (Hierarchical)' AS SNOWFLAKE_SCHEMA

UNION ALL

SELECT
    'Total Dimension Tables',
    '2 Tables',
    '5 Tables'

UNION ALL

SELECT
    'Joins for Category Revenue',
    '2 Joins (Fact + 2 Dims)',
    '5 Joins (Fact + 4 Dims)'

UNION ALL

SELECT
    'Data Redundancy',
    'Higher (Repeated text)',
    'Lower (Normalized IDs)'

UNION ALL

SELECT
    'Query Simplicity',
    'High (Simple GROUP BY)',
    'Lower (Requires nested FKs)';


--=============================================================================
-- TASK 13 — REGIONAL MANAGER SALES PERFORMANCE
--=============================================================================

SELECT
    D.REGIONAL_MANAGER,
    SUM(F.QUANTITY) AS TOTAL_ITEMS_SOLD,
    SUM(F.TOTAL_AMOUNT) AS TOTAL_SALES_AMOUNT
FROM STAR_FACT_SALES F
JOIN STAR_DIM_STORE D
    ON F.STORE_KEY = D.STORE_KEY
GROUP BY
    D.REGIONAL_MANAGER
ORDER BY
    D.REGIONAL_MANAGER;


--=============================================================================
-- TASK 14 — FULL WAREHOUSE ARCHITECTURE AUDIT
--=============================================================================

SELECT
    'Star Schema' AS SCHEMA_TYPE,
    'STAR_DIM_STORE' AS TABLE_NAME,
    COUNT(*) AS RECORD_COUNT
FROM STAR_DIM_STORE

UNION ALL

SELECT
    'Star Schema',
    'STAR_DIM_PRODUCT',
    COUNT(*)
FROM STAR_DIM_PRODUCT

UNION ALL

SELECT
    'Star Schema',
    'STAR_FACT_SALES',
    COUNT(*)
FROM STAR_FACT_SALES

UNION ALL

SELECT
    'Snowflake Schema',
    'SNOW_DIM_REGION',
    COUNT(*)
FROM SNOW_DIM_REGION

UNION ALL

SELECT
    'Snowflake Schema',
    'SNOW_DIM_STORE',
    COUNT(*)
FROM SNOW_DIM_STORE

UNION ALL

SELECT
    'Snowflake Schema',
    'SNOW_DIM_CATEGORY',
    COUNT(*)
FROM SNOW_DIM_CATEGORY

UNION ALL

SELECT
    'Snowflake Schema',
    'SNOW_DIM_SUBCATEGORY',
    COUNT(*)
FROM SNOW_DIM_SUBCATEGORY

UNION ALL

SELECT
    'Snowflake Schema',
    'SNOW_DIM_PRODUCT',
    COUNT(*)
FROM SNOW_DIM_PRODUCT

UNION ALL

SELECT
    'Snowflake Schema',
    'SNOW_FACT_SALES',
    COUNT(*)
FROM SNOW_FACT_SALES;