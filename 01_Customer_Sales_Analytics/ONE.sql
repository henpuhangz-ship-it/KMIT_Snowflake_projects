CREATE WAREHOUSE SALES_WH
WAREHOUSE_SIZE = 'XSMALL';

CREATE DATABASE CUSTOMER_SALES_DB;
CREATE SCHEMA CUSTOMER_SALES_DB.SALES_SCHEMA

USE WAREHOUSE SALES_WH;
USE DATABASE CUSTOMER_SALES_DB;
USE SCHEMA SALES_SCHEMA;


create file format csv_format
type='csv'
skip_header=1
field_delimiter=',';

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
TYPE = 'CSV'
SKIP_HEADER = 1
FIELD_DELIMITER = ','
FIELD_OPTIONALLY_ENCLOSED_BY = '"';

create stage sales_stage
file_format=csv_format;




create table Customers(
    customer_id integer,
    first_name varchar,
    last_name varchar,
    email varchar,
    phone varchar,
    address varchar
);

create table fooditems(
    food_id integer,
    name varchar,
    description varchar,
    price number(10,2),
    category varchar,
    availability varchar
);

create table orders(
    order_id integer,
    customer_id integer,
    food_id integer,
    quantity integer,
    order_date timestamp,
    status varchar,
    total_amount number(10,2)  
);

list @sales_stage;

copy into customers
from @sales_stage/customers.csv
file_format=csv_format;

copy into fooditems
from @sales_stage/fooditems.csv
file_format=csv_format;

copy into orders
from @sales_stage/orders.csv
file_format=csv_format;

SELECT
    $1, $2, $3, $4, $5, $6, $7
FROM @SALES_STAGE/orders.csv
(FILE_FORMAT => CSV_FORMAT);


select * from customers;
select * from fooditems;
select * from orders;

SELECT
    c.CUSTOMER_ID,
    CONCAT(c.FIRST_NAME, ' ', c.LAST_NAME) AS CUSTOMER_NAME,
    SUM(o.TOTAL_AMOUNT) AS TOTAL_AMOUNT_SPENT
FROM CUSTOMERS c
INNER JOIN ORDERS o
    ON c.CUSTOMER_ID = o.CUSTOMER_ID
GROUP BY
    c.CUSTOMER_ID,
    c.FIRST_NAME,
    c.LAST_NAME
ORDER BY TOTAL_AMOUNT_SPENT DESC
LIMIT 1
;

select 
    sum(total_amount) as total_revenue
from orders;

select 
    f.category,
    sum(total_amount) as total_cat_revenue
from orders o
inner join fooditems f
    on f.food_id=f.food_id
group by f.category
order by total_cat_revenue desc;
    
select 
    status as order_status,
    sum(total_amount) as total_revenue
from orders
group by status
order by total_revenue desc;


SELECT
    c.CUSTOMER_ID,
    CONCAT(c.FIRST_NAME, ' ', c.LAST_NAME) AS CUSTOMER_NAME,
    SUM(o.TOTAL_AMOUNT) AS TOTAL_AMOUNT_SPENT
FROM CUSTOMERS c
INNER JOIN ORDERS o
    ON c.CUSTOMER_ID = o.CUSTOMER_ID
GROUP BY
    c.CUSTOMER_ID,
    c.FIRST_NAME,
    c.LAST_NAME
ORDER BY TOTAL_AMOUNT_SPENT DESC
LIMIT 3
;

SELECT
    c.CUSTOMER_ID,
    CONCAT(c.FIRST_NAME, ' ', c.LAST_NAME) AS CUSTOMER_NAME,
    COUNT(o.ORDER_ID) AS ORDERS_PLACED
FROM CUSTOMERS c
INNER JOIN ORDERS o
    ON c.CUSTOMER_ID = o.CUSTOMER_ID
GROUP BY
    c.CUSTOMER_ID,
    c.FIRST_NAME,
    c.LAST_NAME
ORDER BY ORDERS_PLACED DESC;


SELECT *
FROM ORDERS
WHERE STATUS = 'Delivered';

SELECT
    o.ORDER_ID,
    CONCAT(c.FIRST_NAME, ' ', c.LAST_NAME) AS CUSTOMER_NAME,
    o.ORDER_DATE,
    o.STATUS,
    o.TOTAL_AMOUNT
FROM ORDERS o
INNER JOIN CUSTOMERS c
    ON o.CUSTOMER_ID = c.CUSTOMER_ID
WHERE o.ORDER_DATE > '2026-07-12'
ORDER BY o.ORDER_DATE;

CREATE OR REPLACE VIEW CUSTOMER_SALES_REPORT AS
SELECT
    c.CUSTOMER_ID,
    CONCAT(c.FIRST_NAME, ' ', c.LAST_NAME) AS CUSTOMER_NAME,
    SUM(o.TOTAL_AMOUNT) AS TOTAL_AMOUNT_SPENT
FROM CUSTOMERS c
INNER JOIN ORDERS o
    ON c.CUSTOMER_ID = o.CUSTOMER_ID
GROUP BY
    c.CUSTOMER_ID,
    c.FIRST_NAME,
    c.LAST_NAME;

SELECT *
FROM CUSTOMER_SALES_REPORT;

SELECT *
FROM CUSTOMER_SALES_REPORT
ORDER BY TOTAL_AMOUNT_SPENT DESC;
