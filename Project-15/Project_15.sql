CREATE WAREHOUSE P15_WH
    WAREHOUSE_SIZE = 'XSMALL';
USE WAREHOUSE P15_WH;

CREATE DATABASE P15_DB;
USE DATABASE P15_DB;

CREATE SCHEMA P15_DB.P15_SCHEMA;
USE SCHEMA P15_SCHEMA;


-- TASK 1 — BRONZE DATA LAKE INGESTION & SCHEMA-ON-READ EXPLORATION


CREATE TABLE BRONZE_IOT_STREAMS
(
    INGEST_ID    NUMBER        AUTOINCREMENT PRIMARY KEY,
    RAW_PAYLOAD  VARIANT,
    RECORDED_AT  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Batch 1: INSERT INTO BRONZE_IOT_STREAMS (RAW_PAYLOAD)
SELECT PARSE_JSON('{"payload_id":"PL-801","payload_type":"TELEMATICS","timestamp":"2026-08-01T06:00:00Z","data":{"trip_id":"TRP-101","vehicle_id":"TRK-9001","driver_name":"John Doe","distance_km":450.0,"fuel_consumed_liters":120.0,"speed_avg":75.0}}')
UNION ALL
SELECT PARSE_JSON('{"payload_id":"PL-802","payload_type":"CUSTOMS","timestamp":"2026-08-01T06:30:00Z","data":{"shipment_id":"SHP-5001","vehicle_id":"TRK-9001","destination_country":"CAN","declared_value":85000.00,"duty_pct":5.0,"clearance_status":"CLEARED"}}')
UNION ALL
SELECT PARSE_JSON('{"payload_id":"PL-803","payload_type":"TELEMATICS","timestamp":"2026-08-01T07:00:00Z","data":{"trip_id":"TRP-102","vehicle_id":"TRK-9002","driver_name":"Jane Smith","distance_km":620.0,"fuel_consumed_liters":180.0,"speed_avg":82.0}}')
UNION ALL
SELECT PARSE_JSON('{"payload_id":"PL-804","payload_type":"CUSTOMS","timestamp":"2026-08-01T07:45:00Z","data":{"shipment_id":"SHP-5002","vehicle_id":"TRK-9002","destination_country":"MEX","declared_value":42000.00,"duty_pct":7.5,"clearance_status":"CLEARED"}}');

-- Batch 2: Schema Evolution — driver_fatigue_score & border_clearance_code added (3 records)
INSERT INTO BRONZE_IOT_STREAMS (RAW_PAYLOAD)
SELECT PARSE_JSON('{"payload_id":"PL-805","payload_type":"TELEMATICS","timestamp":"2026-08-01T08:15:00Z","data":{"trip_id":"TRP-103","vehicle_id":"TRK-9003","driver_name":"Robert Brown","distance_km":310.0,"fuel_consumed_liters":95.0,"speed_avg":68.0,"driver_fatigue_score":1.2}}')
UNION ALL
SELECT PARSE_JSON('{"payload_id":"PL-806","payload_type":"CUSTOMS","timestamp":"2026-08-01T08:30:00Z","data":{"shipment_id":"SHP-5003","vehicle_id":"TRK-9003","destination_country":"CAN","declared_value":120000.00,"duty_pct":4.0,"clearance_status":"CLEARED","border_clearance_code":"FAST_PASS_01"}}')
UNION ALL
SELECT PARSE_JSON('{"payload_id":"PL-807","payload_type":"CUSTOMS","timestamp":"2026-08-01T09:00:00Z","data":{"shipment_id":"SHP-5004","vehicle_id":"TRK-9001","destination_country":"MEX","declared_value":15000.00,"duty_pct":7.5,"clearance_status":"HELD_INSPECTION","border_clearance_code":null}}');

-- Batch 3: Valid record only — corrupted one handled in Task 2 (1 record)
INSERT INTO BRONZE_IOT_STREAMS (RAW_PAYLOAD)
SELECT PARSE_JSON('{"payload_id":"PL-808","payload_type":"TELEMATICS","timestamp":"2026-08-01T09:30:00Z","data":{"trip_id":"TRP-104","vehicle_id":"TRK-9004","driver_name":"Alice Green","distance_km":0.0,"fuel_consumed_liters":0.0,"speed_avg":0.0,"driver_fatigue_score":0.0}}');

-- Verify: Expected count = 8
SELECT COUNT(*) AS TOTAL_BRONZE_RECORDS
FROM BRONZE_IOT_STREAMS;

-- Schema-on-Read exploration query
-- Note: fields are nested one level deep inside the "data" object
SELECT
    RAW_PAYLOAD:payload_id::VARCHAR                     AS PAYLOAD_ID,
    RAW_PAYLOAD:payload_type::VARCHAR                   AS PAYLOAD_TYPE,
    RAW_PAYLOAD:timestamp::TIMESTAMP_NTZ                AS EVENT_TIME,
    RAW_PAYLOAD:data.vehicle_id::VARCHAR                AS VEHICLE_ID,
    RAW_PAYLOAD:data.shipment_id::VARCHAR               AS SHIPMENT_ID,
    RAW_PAYLOAD:data.declared_value::NUMBER(12,2)       AS DECLARED_VALUE,
    RAW_PAYLOAD:data.driver_name::VARCHAR               AS DRIVER_NAME,
    RAW_PAYLOAD:data.driver_fatigue_score::NUMBER(5,2)  AS DRIVER_FATIGUE_SCORE,
    RAW_PAYLOAD:data.border_clearance_code::VARCHAR     AS BORDER_CLEARANCE_CODE
FROM BRONZE_IOT_STREAMS
ORDER BY EVENT_TIME;



-- TASK 2 — DEAD-LETTER QUEUE QUARANTINE STRATEGY
CREATE TABLE QUARANTINE_IOT_PAYLOADS
(
    QUARANTINE_ID    NUMBER       AUTOINCREMENT PRIMARY KEY,
    RAW_RECORD_TEXT  VARCHAR,
    REASON           VARCHAR(100),
    QUARANTINE_TIME  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert the malformed record directly
INSERT INTO QUARANTINE_IOT_PAYLOADS (RAW_RECORD_TEXT, REASON)
VALUES
(
    'MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR',
    'MALFORMED_JSON_BODY'
);

-- Verify quarantine
SELECT
    QUARANTINE_ID,
    RAW_RECORD_TEXT,
    REASON
FROM QUARANTINE_IOT_PAYLOADS;

-- Production pattern: auto-route bad records using TRY_PARSE_JSON
-- If raw text was first landed in a staging VARCHAR table:

CREATE TABLE STAGING_RAW_TEXT
(
    RAW_TEXT VARCHAR
);

INSERT INTO STAGING_RAW_TEXT (RAW_TEXT) VALUES
('{"payload_id":"PL-808","payload_type":"TELEMATICS","timestamp":"2026-08-01T09:30:00Z","data":{"trip_id":"TRP-104","vehicle_id":"TRK-9004","driver_name":"Alice Green","distance_km":0.0,"fuel_consumed_liters":0.0,"speed_avg":0.0,"driver_fatigue_score":0.0}}'),
('{"MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR"}');

-- Valid records (go to Bronze)
SELECT TRY_PARSE_JSON(RAW_TEXT) AS PARSED, RAW_TEXT
FROM STAGING_RAW_TEXT
WHERE TRY_PARSE_JSON(RAW_TEXT) IS NOT NULL;

-- Corrupted records (go to Quarantine)
SELECT RAW_TEXT AS RAW_RECORD_TEXT, 'MALFORMED_JSON_BODY' AS REASON
FROM STAGING_RAW_TEXT
WHERE TRY_PARSE_JSON(RAW_TEXT) IS NULL;



-- TASK 3 — SILVER LAYER ETL: SCHEMA-ON-WRITE CUSTOMS CLEARANCE


CREATE TABLE SILVER_CUSTOMS_CLEARANCE
(
    SHIPMENT_ID       VARCHAR(20),
    PAYLOAD_ID        VARCHAR(20),
    VEHICLE_ID        VARCHAR(20),
    DESTINATION_COUNTRY VARCHAR(10),
    DECLARED_VALUE    NUMBER(12,2),
    DUTY_PCT          NUMBER(5,2),
    DUTY_AMOUNT_DUE   NUMBER(12,2),
    BORDER_CODE       VARCHAR(50),
    CLEARANCE_STATUS  VARCHAR(30)
);

INSERT INTO SILVER_CUSTOMS_CLEARANCE
(
    SHIPMENT_ID,
    PAYLOAD_ID,
    VEHICLE_ID,
    DESTINATION_COUNTRY,
    DECLARED_VALUE,
    DUTY_PCT,
    DUTY_AMOUNT_DUE,
    BORDER_CODE,
    CLEARANCE_STATUS
)
SELECT
    RAW_PAYLOAD:data.shipment_id::VARCHAR                                           AS SHIPMENT_ID,
    RAW_PAYLOAD:payload_id::VARCHAR                                                 AS PAYLOAD_ID,
    RAW_PAYLOAD:data.vehicle_id::VARCHAR                                            AS VEHICLE_ID,
    RAW_PAYLOAD:data.destination_country::VARCHAR                                   AS DESTINATION_COUNTRY,
    RAW_PAYLOAD:data.declared_value::NUMBER(12,2)                                   AS DECLARED_VALUE,
    RAW_PAYLOAD:data.duty_pct::NUMBER(5,2)                                          AS DUTY_PCT,
    RAW_PAYLOAD:data.declared_value::NUMBER(12,2)
        * (RAW_PAYLOAD:data.duty_pct::NUMBER(5,2) / 100)                           AS DUTY_AMOUNT_DUE,
    NULLIF(RAW_PAYLOAD:data.border_clearance_code::VARCHAR, 'null')                 AS BORDER_CODE,
    RAW_PAYLOAD:data.clearance_status::VARCHAR                                      AS CLEARANCE_STATUS
FROM BRONZE_IOT_STREAMS
WHERE RAW_PAYLOAD:payload_type::VARCHAR = 'CUSTOMS';

-- Verify Silver
SELECT * FROM SILVER_CUSTOMS_CLEARANCE;


-- ============================================================================
-- TASK 4 — GOLD LAYER STRATEGIC AGGREGATIONS

CREATE TABLE GOLD_COUNTRY_DUTY_SUMMARY
(
    DEST_COUNTRY          VARCHAR(10),
    TOTAL_CLEARED_VAL     NUMBER(12,2),
    TOTAL_DUTIES_COLLECTED NUMBER(12,2),
    AVG_DUTY_RATE_PCT     NUMBER(5,2),
    CLEARED_SHIPMENTS     NUMBER
);

INSERT INTO GOLD_COUNTRY_DUTY_SUMMARY
(
    DEST_COUNTRY,
    TOTAL_CLEARED_VAL,
    TOTAL_DUTIES_COLLECTED,
    AVG_DUTY_RATE_PCT,
    CLEARED_SHIPMENTS
)
SELECT
    DESTINATION_COUNTRY                                         AS DEST_COUNTRY,
    SUM(DECLARED_VALUE)                                         AS TOTAL_CLEARED_VAL,
    SUM(DUTY_AMOUNT_DUE)                                        AS TOTAL_DUTIES_COLLECTED,
    ROUND(SUM(DUTY_AMOUNT_DUE) / NULLIF(SUM(DECLARED_VALUE), 0) * 100, 2)
                                                                AS AVG_DUTY_RATE_PCT,
    COUNT(*)                                                    AS CLEARED_SHIPMENTS
FROM SILVER_CUSTOMS_CLEARANCE
WHERE CLEARANCE_STATUS = 'CLEARED'
GROUP BY DESTINATION_COUNTRY
ORDER BY DESTINATION_COUNTRY;

-- Verify Gold
SELECT * FROM GOLD_COUNTRY_DUTY_SUMMARY;


-- ============================================================================
-- TASK 5 — DISASTER RECOVERY VIA SNOWFLAKE TIME-TRAVEL AUDITING
============

-- Step 1: Corruption simulation
UPDATE SILVER_CUSTOMS_CLEARANCE
SET CLEARANCE_STATUS = 'REJECTED'
WHERE DESTINATION_COUNTRY = 'CAN';

-- Step 2: Time-Travel inspection — view state before corruption
-- Run immediately after the UPDATE (increase offset if there's a delay)
SELECT
    SHIPMENT_ID,
    DESTINATION_COUNTRY,
    CLEARANCE_STATUS
FROM SILVER_CUSTOMS_CLEARANCE
AT (OFFSET => -300)
WHERE DESTINATION_COUNTRY = 'CAN';

-- Step 3: Recovery using MERGE + Time-Travel snapshot as source
MERGE INTO SILVER_CUSTOMS_CLEARANCE AS TARGET
USING (
    SELECT SHIPMENT_ID, CLEARANCE_STATUS
    FROM SILVER_CUSTOMS_CLEARANCE
    AT (OFFSET => -300)
    WHERE DESTINATION_COUNTRY = 'CAN'
) AS SOURCE
ON TARGET.SHIPMENT_ID = SOURCE.SHIPMENT_ID
WHEN MATCHED THEN
    UPDATE SET TARGET.CLEARANCE_STATUS = SOURCE.CLEARANCE_STATUS;

-- Post-recovery audit: Expected CAN = 2 CLEARED, 0 REJECTED | MEX = 1 CLEARED, 0 REJECTED
SELECT
    DESTINATION_COUNTRY                                             AS DEST_COUNTRY,
    COUNT(CASE WHEN CLEARANCE_STATUS = 'CLEARED'  THEN 1 END)      AS CLEARED_COUNT,
    COUNT(CASE WHEN CLEARANCE_STATUS = 'REJECTED' THEN 1 END)      AS REJECTED_COUNT
FROM SILVER_CUSTOMS_CLEARANCE
WHERE DESTINATION_COUNTRY IN ('CAN', 'MEX')
GROUP BY DESTINATION_COUNTRY
ORDER BY DESTINATION_COUNTRY;


-- -- TASK 6 — END-TO-END PIPELINE LINEAGE & RECONCILIATION AUDIT


SELECT
    BRONZE.BRONZE_GROSS_TOTAL,
    SILVER.SILVER_GROSS_TOTAL,
    GOLD.GOLD_GROSS_TOTAL,
    CASE
        WHEN BRONZE.BRONZE_GROSS_TOTAL = SILVER.SILVER_GROSS_TOTAL
        THEN 'TRUE'
        ELSE 'FALSE'
    END AS RECONCILED_FLAG
FROM
(
    SELECT SUM(RAW_PAYLOAD:data.declared_value::NUMBER(12,2)) AS BRONZE_GROSS_TOTAL
    FROM BRONZE_IOT_STREAMS
    WHERE RAW_PAYLOAD:payload_type::VARCHAR = 'CUSTOMS'
) AS BRONZE

CROSS JOIN
(
    SELECT SUM(DECLARED_VALUE) AS SILVER_GROSS_TOTAL
    FROM SILVER_CUSTOMS_CLEARANCE
) AS SILVER

CROSS JOIN
(
    SELECT SUM(TOTAL_CLEARED_VAL) AS GOLD_GROSS_TOTAL
    FROM GOLD_COUNTRY_DUTY_SUMMARY
) AS GOLD;
