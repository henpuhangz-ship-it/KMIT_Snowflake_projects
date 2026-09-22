CREATE WAREHOUSE P14A_WH
WAREHOUSE_SIZE ='XSMALL';
USE WAREHOUSE P14A_WH;

CREATE DATABASE P14A_DB;
USE DATABASE P14A_DB;

CREATE SCHEMA P14A_DB.P14A_SCHEMA;
USE SCHEMA P14A_SCHEMA;


CREATE TABLE LAKE_RAW_EVENTS
(
    RAW_EVENT VARIANT
);

-- Batch 1: 
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT)
SELECT PARSE_JSON('{"event_id":"EVT-8001","timestamp":"2026-07-01T08:15:00Z","user_id":1001,"page":"checkout","action":"purchase","order":{"total":12500.00,"shipping_cost":250.00,"tax":625.00,"items":2}}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8002","timestamp":"2026-07-01T08:20:00Z","user_id":1002,"page":"product_detail","action":"view","order":null}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8003","timestamp":"2026-07-01T08:35:00Z","user_id":1003,"page":"cart","action":"add_to_cart","order":null}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8004","timestamp":"2026-07-01T09:10:00Z","user_id":1004,"page":"checkout","action":"purchase","order":{"total":45000.00,"shipping_cost":500.00,"tax":2250.00,"items":5}}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8005","timestamp":"2026-07-01T09:45:00Z","user_id":1001,"page":"product_detail","action":"view","order":null}');

-- Batch 2: Schema Evolution — promo_code & discount_amount added (5 events)
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT)
SELECT PARSE_JSON('{"event_id":"EVT-8006","timestamp":"2026-07-02T10:00:00Z","user_id":1005,"page":"checkout","action":"purchase","order":{"total":18000.00,"shipping_cost":300.00,"tax":900.00,"items":3},"promo_code":"SUMMER20","discount_amount":3600.00}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8007","timestamp":"2026-07-02T10:15:00Z","user_id":1002,"page":"checkout","action":"purchase","order":{"total":8500.00,"shipping_cost":150.00,"tax":425.00,"items":1},"promo_code":"WELCOME10","discount_amount":850.00}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8008","timestamp":"2026-07-02T10:30:00Z","user_id":1006,"page":"cart","action":"add_to_cart","order":null,"promo_code":null,"discount_amount":0.00}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8009","timestamp":"2026-07-02T11:00:00Z","user_id":1003,"page":"checkout","action":"purchase","order":{"total":32000.00,"shipping_cost":400.00,"tax":1600.00,"items":4},"promo_code":"FESTIVE15","discount_amount":4800.00}')
UNION ALL
SELECT PARSE_JSON('{"event_id":"EVT-8010","timestamp":"2026-07-02T11:20:00Z","user_id":1007,"page":"product_detail","action":"view","order":null,"promo_code":null,"discount_amount":0.00}');

--BATCH 3
INSERT INTO LAKE_RAW_EVENTS(RAW_EVENT)
SELECT
PARSE_JSON('{"event_id":"EVT-8011","timestamp":"2026-07-03T12:00:00Z","user_id":1008,"page":"checkout","action":"purchase","order":{"total":0.00,"shipping_cost":0.00,"tax":0.00,"items":0},"promo_code":"FREEPASS","discount_amount":0.00}');

SELECT COUNT(*) AS TOTAL_RAW_RECORD_CT
FROM LAKE_RAW_EVENTS;

--TASK 2

SELECT
    RAW_EVENT:event_id::VARCHAR                     AS EVENT_ID,
    RAW_EVENT:timestamp::TIMESTAMP_NTZ              AS EVENT_TIME,
    RAW_EVENT:user_id::NUMBER                       AS USER_ID,
    RAW_EVENT:action::VARCHAR                       AS ACTION,
    RAW_EVENT:order.total::NUMBER(12,2)             AS ORDER_TOTAL,
    NULLIF(RAW_EVENT:promo_code::VARCHAR, 'null')   AS PROMO_CODE
FROM LAKE_RAW_EVENTS
ORDER BY EVENT_TIME;

--TASK 3
SELECT
    RAW_EVENT:event_id::VARCHAR                             AS EVENT_ID,
    RAW_EVENT:order.total::NUMBER(12,2)                     AS ORDER_TOTAL,
    RAW_EVENT:order.shipping_cost::NUMBER(12,2)             AS SHIPPING_COST,
    RAW_EVENT:order.tax::NUMBER(12,2)                       AS TAX,
    COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2), 0)    AS DISCOUNT_AMOUNT,

    RAW_EVENT:order.total::NUMBER(12,2)
    - RAW_EVENT:order.shipping_cost::NUMBER(12,2)
    - RAW_EVENT:order.tax::NUMBER(12,2)
    - COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2), 0)  AS NET_REVENUE

FROM LAKE_RAW_EVENTS
WHERE RAW_EVENT:order.total::NUMBER(12,2) > 0
ORDER BY EVENT_ID;

--TASK 4


SELECT
    COUNT(*)
    AS TOTAL_EVENTS,

    COUNT(
        CASE WHEN RAW_EVENT:action::VARCHAR = 'purchase' THEN 1 END
    )
    AS TOTAL_PURCHASES,

    ROUND(
        COUNT(CASE WHEN RAW_EVENT:action::VARCHAR = 'purchase' THEN 1 END)
        / COUNT(*) * 100,
        2
    )                                                                
    AS CONVERSION_RATE_PCT,

    SUM(
        CASE WHEN RAW_EVENT:order.total::NUMBER(12,2) > 0
             THEN RAW_EVENT:order.total::NUMBER(12,2)
             ELSE 0 END
    )                                                                
    AS TOTAL_GROSS_REVENUE,

    SUM(
        CASE WHEN RAW_EVENT:order.total::NUMBER(12,2) > 0
             THEN RAW_EVENT:order.total::NUMBER(12,2)
             ELSE 0 END
    )
    / NULLIF(
        COUNT(CASE WHEN RAW_EVENT:action::VARCHAR = 'purchase' THEN 1 END),
        0
    )                                                                
    AS AVERAGE_ORDER_VALUE

FROM LAKE_RAW_EVENTS;


--===========================TASK 5===================================
CREATE TABLE DW_STRUCTURED_EVENTS
(
    EVENT_KEY        NUMBER        AUTOINCREMENT PRIMARY KEY,
    EVENT_ID         VARCHAR(50),
    EVENT_TIME       TIMESTAMP_NTZ,
    USER_ID          NUMBER,
    PAGE             VARCHAR(100),
    ACTION           VARCHAR(50),
    ORDER_TOTAL      NUMBER(12,2),
    SHIPPING_COST    NUMBER(12,2),
    TAX              NUMBER(12,2),
    ORDER_ITEMS      NUMBER,
    PROMO_CODE       VARCHAR(50),
    DISCOUNT_AMOUNT  NUMBER(12,2),
    NET_REVENUE      NUMBER(12,2)
);

-- Backfill: 
INSERT INTO DW_STRUCTURED_EVENTS
(
    EVENT_ID,
    EVENT_TIME,
    USER_ID,
    PAGE,
    ACTION,
    ORDER_TOTAL,
    SHIPPING_COST,
    TAX,
    ORDER_ITEMS,
    PROMO_CODE,
    DISCOUNT_AMOUNT,
    NET_REVENUE
)
SELECT
    RAW_EVENT:event_id::VARCHAR                                     AS EVENT_ID,
    RAW_EVENT:timestamp::TIMESTAMP_NTZ                              AS EVENT_TIME,
    RAW_EVENT:user_id::NUMBER                                       AS USER_ID,
    RAW_EVENT:page::VARCHAR                                         AS PAGE,
    RAW_EVENT:action::VARCHAR                                       AS ACTION,
    COALESCE(RAW_EVENT:order.total::NUMBER(12,2),       0)          AS ORDER_TOTAL,
    COALESCE(RAW_EVENT:order.shipping_cost::NUMBER(12,2), 0)        AS SHIPPING_COST,
    COALESCE(RAW_EVENT:order.tax::NUMBER(12,2),         0)          AS TAX,
    COALESCE(RAW_EVENT:order.items::NUMBER,             0)          AS ORDER_ITEMS,
    NULLIF(RAW_EVENT:promo_code::VARCHAR, 'null')                   AS PROMO_CODE,
    COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2),   0)          AS DISCOUNT_AMOUNT,

    -- NET_REVENUE computed at write time (Schema-on-Write)
    COALESCE(RAW_EVENT:order.total::NUMBER(12,2), 0)
    - COALESCE(RAW_EVENT:order.shipping_cost::NUMBER(12,2), 0)
    - COALESCE(RAW_EVENT:order.tax::NUMBER(12,2), 0)
    - COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2), 0)          AS NET_REVENUE

FROM LAKE_RAW_EVENTS;

-- Verify: Expected 11 records, NET_REVENUE total = 99350.00
SELECT
    COUNT(*)          AS STORED_RECORDS_QTY,
    SUM(NET_REVENUE)  AS TOTAL_NET_REVENUE
FROM DW_STRUCTURED_EVENTS;

--==============TASK 6========================

CREATE TABLE QUARANTINE_RAW_EVENTS
(
    QUARANTINE_ID    NUMBER        AUTOINCREMENT PRIMARY KEY,
    RAW_RECORD_TEXT  VARCHAR,
    REASON           VARCHAR(100),
    QUARANTINE_TIME  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);


INSERT INTO QUARANTINE_RAW_EVENTS (RAW_RECORD_TEXT, REASON)
VALUES
(
    'INVALID_JSON_PAYLOAD_MALFORMED_STRING',
    'MALFORMED_JSON_BODY'
);


SELECT
    QUARANTINE_ID,
    RAW_RECORD_TEXT,
    REASON
FROM QUARANTINE_RAW_EVENTS;

-----