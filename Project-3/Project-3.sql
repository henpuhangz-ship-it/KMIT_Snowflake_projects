CREATE WAREHOUSE ENTERPRISE_WH
WAREHOUSE_SIZE = 'XSMALL';


CREATE DATABASE ENTERPRISE_DB;
CREATE SCHEMA ENTERPRISE_DB.SALES_SCHEMA;

USE WAREHOUSE ENTERPRISE_WH;
USE DATABASE ENTERPRISE_DB;
USE SCHEMA SALES_SCHEMA;

CREATE FILE FORMAT CSV_FORMAT
TYPE = 'CSV'
SKIP_HEADER = 1
FIELD_DELIMITER = ',';

CREATE STAGE SALES_STAGE
FILE_FORMAT = CSV_FORMAT;

LIST @SALES_STAGE;

CREATE TABLE CUSTOMERS (
    customer_id INT,
    customer_name VARCHAR,
    city VARCHAR,
    membership VARCHAR
);

CREATE TABLE PRODUCTS (
    product_id INT,
    product_name VARCHAR,
    category VARCHAR,
    price NUMBER(10,2)
);

CREATE TABLE BRANCHES (
    branch_id INT,
    branch_name VARCHAR,
    state VARCHAR
);

CREATE TABLE SALES (
    sale_id INT,
    customer_id INT,
    product_id INT,
    branch_id INT,
    quantity INT,
    sale_date DATE,
    total_amount NUMBER(12,2)
);

CREATE TABLE SALES_STAGE_TABLE (
    sale_id INT,
    customer_id INT,
    product_id INT,
    branch_id INT,
    quantity INT,
    sale_date DATE,
    total_amount NUMBER(12,2)
);


/*PHASE2------------------------------------------------*/

COPY INTO CUSTOMERS
FROM @SALES_STAGE/customers.csv
FILE_FORMAT = CSV_FORMAT;

SELECT *
FROM CUSTOMERS
ORDER BY customer_id;

COPY INTO PRODUCTS
FROM @SALES_STAGE/products.csv
FILE_FORMAT = CSV_FORMAT;

COPY INTO BRANCHES
FROM @SALES_STAGE/branches.csv
FILE_FORMAT = CSV_FORMAT;

COPY INTO SALES
FROM @SALES_STAGE/sales_history.csv
FILE_FORMAT = CSV_FORMAT;

SELECT *
FROM SALES
ORDER BY sale_id;

/*--------------PHASE 3-------------------------*/

CREATE STREAM SALES_STREAM
ON TABLE SALES_STAGE_TABLE;

COPY INTO SALES_STAGE_TABLE
FROM @SALES_STAGE/new_sales.csv
FILE_FORMAT = CSV_FORMAT;

SELECT *
FROM SALES_STAGE_TABLE
ORDER BY sale_id;


SELECT
    sale_id,
    customer_id,
    product_id,
    branch_id,
    quantity,
    sale_date,
    total_amount,
    METADATA$ACTION,
    METADATA$ISUPDATE
FROM SALES_STREAM;

/*MERGE INTO SALES*/

MERGE INTO SALES AS target
USING SALES_STREAM AS source
ON target.sale_id = source.sale_id

WHEN NOT MATCHED THEN

    INSERT (
        sale_id,
        customer_id,
        product_id,
        branch_id,
        quantity,
        sale_date,
        total_amount
    )

    VALUES (
        source.sale_id,
        source.customer_id,
        source.product_id,
        source.branch_id,
        source.quantity,
        source.sale_date,
        source.total_amount
    );

SELECT *
FROM SALES
ORDER BY sale_id;

/* PHASE 4 */

SELECT
    sale_id,
    COUNT(*) AS duplicate_count
FROM SALES
GROUP BY sale_id
HAVING COUNT(*) > 1;

SELECT
    s.sale_id,
    s.customer_id
FROM SALES s
LEFT JOIN CUSTOMERS c
    ON s.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT
    s.sale_id,
    s.product_id
FROM SALES s
LEFT JOIN PRODUCTS p
    ON s.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS newly_inserted_records
FROM SALES_STAGE_TABLE;

SELECT COUNT(*)
FROM SALES;

DELETE FROM SALES
WHERE sale_id = 10;

SELECT *
FROM SALES;

SELECT *
FROM SALES
AT (OFFSET => -60)
WHERE sale_id = 10;

INSERT INTO SALES
SELECT *
FROM SALES
AT (OFFSET => -300)
WHERE sale_id = 10;

SELECT *
FROM SALES
WHERE sale_id = 10;


/*phase 6----------------------------*/

CREATE TABLE SALES_TEST
CLONE SALES;

SELECT *
FROM SALES_TEST
ORDER BY sale_id;

INSERT INTO SALES_TEST
VALUES (
    11,
    1,
    103,
    1,
    3,
    '2026-07-11',
    4500
);

SELECT *
FROM SALES_TEST
WHERE sale_id = 11;

SELECT *
FROM SALES
WHERE sale_id = 11;

/*---------------PHASE 7-----------------------------*/


-- 
CREATE TASK DAILY_SALES_LOAD
WAREHOUSE = ENTERPRISE_WH
SCHEDULE = 'USING CRON 0 2 * * * Asia/Kolkata'
AS
MERGE INTO SALES AS target
USING SALES_STAGE_TABLE AS source
ON target.sale_id = source.sale_id

WHEN NOT MATCHED THEN
    INSERT (
        sale_id,
        customer_id,
        product_id,
        branch_id,
        quantity,
        sale_date,
        total_amount
    )
    VALUES (
        source.sale_id,
        source.customer_id,
        source.product_id,
        source.branch_id,
        source.quantity,
        source.sale_date,
        source.total_amount
    );


ALTER TASK DAILY_SALES_LOAD RESUME;


-- 
SHOW TASKS;

SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
ORDER BY SCHEDULED_TIME DESC;


/*
   PHASE 8 — BUSINESS ANALYTICS
    */

-- 
SELECT
    c.customer_id,
    c.customer_name,
    SUM(s.total_amount) AS total_revenue
FROM SALES s
JOIN CUSTOMERS c
    ON s.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.customer_name
ORDER BY total_revenue DESC;


-- 
SELECT
    b.branch_id,
    b.branch_name,
    SUM(s.total_amount) AS total_revenue
FROM SALES s
JOIN BRANCHES b
    ON s.branch_id = b.branch_id
GROUP BY
    b.branch_id,
    b.branch_name
ORDER BY total_revenue DESC;


-- 
SELECT
    p.product_id,
    p.product_name,
    SUM(s.total_amount) AS total_revenue
FROM SALES s
JOIN PRODUCTS p
    ON s.product_id = p.product_id
GROUP BY
    p.product_id,
    p.product_name
ORDER BY total_revenue DESC;


-- 
SELECT
    DATE_TRUNC('MONTH', sale_date) AS month,
    SUM(total_amount) AS monthly_revenue
FROM SALES
GROUP BY DATE_TRUNC('MONTH', sale_date)
ORDER BY month;


-- 
SELECT
    c.customer_id,
    c.customer_name,
    SUM(s.total_amount) AS revenue
FROM SALES s
JOIN CUSTOMERS c
    ON s.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.customer_name
ORDER BY revenue DESC
LIMIT 1;


-- 
SELECT
    b.branch_id,
    b.branch_name,
    SUM(s.total_amount) AS revenue
FROM SALES s
JOIN BRANCHES b
    ON s.branch_id = b.branch_id
GROUP BY
    b.branch_id,
    b.branch_name
ORDER BY revenue DESC
LIMIT 1;


-- 
SELECT
    p.product_id,
    p.product_name,
    SUM(s.total_amount) AS revenue
FROM SALES s
JOIN PRODUCTS p
    ON s.product_id = p.product_id
GROUP BY
    p.product_id,
    p.product_name
ORDER BY revenue DESC
LIMIT 5;


-- 
SELECT
    c.customer_id,
    c.customer_name,
    COUNT(s.sale_id) AS purchase_frequency
FROM SALES s
JOIN CUSTOMERS c
    ON s.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.customer_name
ORDER BY purchase_frequency DESC;


-- 
SELECT
    sale_id,
    sale_date,
    total_amount,
    SUM(total_amount) OVER (
        ORDER BY sale_date, sale_id
    ) AS running_revenue
FROM SALES
ORDER BY sale_date, sale_id;


-- 
WITH customer_revenue AS (
    SELECT
        c.customer_id,
        c.customer_name,
        SUM(s.total_amount) AS revenue
    FROM SALES s
    JOIN CUSTOMERS c
        ON s.customer_id = c.customer_id
    GROUP BY
        c.customer_id,
        c.customer_name
)
SELECT
    customer_id,
    customer_name,
    revenue,
    RANK() OVER (
        ORDER BY revenue DESC
    ) AS customer_rank
FROM customer_revenue
ORDER BY customer_rank;


/*
   PHASE 9 — VIEWS=== */

CREATE VIEW CUSTOMER_REVENUE AS
SELECT
    c.customer_id,
    c.customer_name,
    SUM(s.total_amount) AS revenue
FROM SALES s
JOIN CUSTOMERS c
    ON s.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.customer_name;



SELECT *
FROM CUSTOMER_REVENUE
ORDER BY revenue DESC;



CREATE MATERIALIZED VIEW BRANCH_REVENUE AS
SELECT
    branch_id,
    SUM(total_amount) AS revenue
FROM SALES
GROUP BY branch_id;


SELECT *
FROM BRANCH_REVENUE
ORDER BY revenue DESC;


SELECT
    b.branch_name,
    br.revenue
FROM BRANCH_REVENUE br
JOIN BRANCHES b
    ON br.branch_id = b.branch_id
ORDER BY br.revenue DESC;