CREATE WAREHOUSE P16_WH
WAREHOUSE_SIZE='XSMALL';


CREATE DATABASE IF NOT EXISTS HEALTHCARE_PIPELINE_DB;

USE WAREHOUSE P16_WH;
USE DATABASE HEALTHCARE_PIPELINE_DB;

CREATE SCHEMA IF NOT EXISTS CLAIMS_CORE;

USE SCHEMA CLAIMS_CORE;

--===========================TASK 1-==============================

CREATE TABLE BRONZE_RAW_CLAIMS
(
    INGEST_ID NUMBER AUTOINCREMENT,
    PAYLOAD     VARIANT,
    LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);


INSERT INTO BRONZE_RAW_CLAIMS(PAYLOAD)
SELECT PARSE_JSON(column1)
from VALUES
('{"claim_id":"CLM-301","submitted_at":"2026-08-10T08:00:00Z","patient_id":5001,"provider_id":"PRV-10","diagnosis_code":"ICD-10-A","billed_amount":15000.00,"copay_amount":500.00,"status":"PENDING"}'),
('{"claim_id":"CLM-302","submitted_at":"2026-08-10T08:15:00Z","patient_id":5002,"provider_id":"PRV-11","diagnosis_code":"ICD-10-B","billed_amount":8500.00,"copay_amount":300.00,"status":"APPROVED"}'),
('{"claim_id":"CLM-303","submitted_at":"2026-08-10T08:30:00Z","patient_id":5003,"provider_id":"PRV-10","diagnosis_code":"ICD-10-C","billed_amount":45000.00,"copay_amount":1500.00,"status":"PENDING"}'),
('{"claim_id":"CLM-304","submitted_at":"2026-08-10T09:00:00Z","patient_id":5004,"provider_id":"PRV-12","diagnosis_code":"ICD-10-A","billed_amount":3200.00,"copay_amount":100.00,"status":"APPROVED"}');

INSERT INTO BRONZE_RAW_CLAIMS (PAYLOAD)
SELECT PARSE_JSON(column1)
FROM VALUES
('{"claim_id":"CLM-301","submitted_at":"2026-08-10T08:00:00Z","patient_id":5001,"provider_id":"PRV-10","diagnosis_code":"ICD-10-A","billed_amount":15000.00,"copay_amount":500.00,"status":"APPROVED"}'),
('{"claim_id":"CLM-303","submitted_at":"2026-08-10T08:30:00Z","patient_id":5003,"provider_id":"PRV-10","diagnosis_code":"ICD-10-C","billed_amount":45000.00,"copay_amount":1500.00,"status":"DENIED"}'),
('{"claim_id":"CLM-305","submitted_at":"2026-08-10T10:00:00Z","patient_id":5005,"provider_id":"PRV-11","diagnosis_code":"ICD-10-B","billed_amount":120000.00,"copay_amount":2500.00,"status":"APPROVED"}');
INSERT INTO BRONZE_RAW_CLAIMS (PAYLOAD)
SELECT PARSE_JSON(column1)
FROM VALUES
('{"claim_id":"CLM-306","submitted_at":"2026-08-10T10:30:00Z","patient_id":5002,"provider_id":"PRV-12","diagnosis_code":"ICD-10-A","billed_amount":6000.00,"copay_amount":200.00,"status":"APPROVED"}');

SELECT COUNT(*) FROM BRONZE_RAW_CLAIMS;

SELECT *
FROM BRONZE_RAW_CLAIMS
ORDER BY INGEST_ID;
--========================TASK 2===================================================
CREATE TABLE QUARANTINE_CLAIMS_PAYLOADS
(
    QUARANTINE_ID NUMBER AUTOINCREMENT,
    RAW_RECORD_TEXT VARCHAR,
    REASON VARCHAR
);

INSERT INTO QUARANTINE_CLAIMS_PAYLOADS
(
    RAW_RECORD_TEXT,
    REASON
)
SELECT
    column1,
    'MALFORMED_JSON_BODY'
FROM VALUES
    (
        'INVALID_PAYLOAD_UNPARSEABLE_STRING'
    )
WHERE TRY_PARSE_JSON(column1) IS NULL;

SELECT * FROM QUARANTINE_CLAIMS_PAYLOADS;




--========================TASK 3===================================================
CREATE STREAM STRM_BRONZE_CLAIMS
ON TABLE BRONZE_RAW_CLAIMS;

-- Batch 1
INSERT INTO BRONZE_RAW_CLAIMS(PAYLOAD)
SELECT PARSE_JSON(column1)
FROM VALUES
('{"claim_id":"CLM-301","submitted_at":"2026-08-10T08:00:00Z","patient_id":5001,"provider_id":"PRV-10","diagnosis_code":"ICD-10-A","billed_amount":15000.00,"copay_amount":500.00,"status":"PENDING"}'),
('{"claim_id":"CLM-302","submitted_at":"2026-08-10T08:15:00Z","patient_id":5002,"provider_id":"PRV-11","diagnosis_code":"ICD-10-B","billed_amount":8500.00,"copay_amount":300.00,"status":"APPROVED"}'),
('{"claim_id":"CLM-303","submitted_at":"2026-08-10T08:30:00Z","patient_id":5003,"provider_id":"PRV-10","diagnosis_code":"ICD-10-C","billed_amount":45000.00,"copay_amount":1500.00,"status":"PENDING"}'),
('{"claim_id":"CLM-304","submitted_at":"2026-08-10T09:00:00Z","patient_id":5004,"provider_id":"PRV-12","diagnosis_code":"ICD-10-A","billed_amount":3200.00,"copay_amount":100.00,"status":"APPROVED"}');

-- Batch 2
INSERT INTO BRONZE_RAW_CLAIMS(PAYLOAD)
SELECT PARSE_JSON(column1)
FROM VALUES
('{"claim_id":"CLM-301","submitted_at":"2026-08-10T08:00:00Z","patient_id":5001,"provider_id":"PRV-10","diagnosis_code":"ICD-10-A","billed_amount":15000.00,"copay_amount":500.00,"status":"APPROVED"}'),
('{"claim_id":"CLM-303","submitted_at":"2026-08-10T08:30:00Z","patient_id":5003,"provider_id":"PRV-10","diagnosis_code":"ICD-10-C","billed_amount":45000.00,"copay_amount":1500.00,"status":"DENIED"}'),
('{"claim_id":"CLM-305","submitted_at":"2026-08-10T10:00:00Z","patient_id":5005,"provider_id":"PRV-11","diagnosis_code":"ICD-10-B","billed_amount":120000.00,"copay_amount":2500.00,"status":"APPROVED"}');

-- Batch 3
INSERT INTO BRONZE_RAW_CLAIMS(PAYLOAD)
SELECT PARSE_JSON(column1)
FROM VALUES
('{"claim_id":"CLM-306","submitted_at":"2026-08-10T10:30:00Z","patient_id":5002,"provider_id":"PRV-12","diagnosis_code":"ICD-10-A","billed_amount":6000.00,"copay_amount":200.00,"status":"APPROVED"}');

CREATE TABLE SILVER_CLAIMS_TRANSACTIONS
(
    CLAIM_ID            VARCHAR,
    SUBMITTED_AT        TIMESTAMP_TZ,
    PATIENT_ID          NUMBER,
    PROVIDER_ID         VARCHAR,
    DIAGNOSIS_CODE      VARCHAR, 
    BILLED_AMOUNT       NUMBER(18,2),
    COPAY_AMOUNT        NUMBER(18,2),
    NET_PAYABLE_AMOUNT  NUMBER(18,2),
    STATUS              VARCHAR
);

INSERT INTO SILVER_CLAIMS_TRANSACTIONS
(
        CLAIM_ID,
    SUBMITTED_AT,
    PATIENT_ID,
    PROVIDER_ID,
    DIAGNOSIS_CODE,
    BILLED_AMOUNT,
    COPAY_AMOUNT,
    NET_PAYABLE_AMOUNT,
    STATUS
)
SELECT  
    PAYLOAD:claim_id::VARCHAR as CLAIM_ID,
    PAYLOAD:submitted_at::TIMESTAMP_TZ as  SUBMITTED_AT,
    PAYLOAD:patient_id::NUMBER as PATIENT_ID,
    PAYLOAD:provider_id::VARCHAR as PROVIDER_ID,
    PAYLOAD:diagnosis_code::VARCHAR AS DIAGNOSIS_CODE,
    PAYLOAD:billed_amount::NUMBER(18,2) AS BILLED_AMOUNT,
    PAYLOAD:copay_amount::NUMBER(18,2) AS COPAY_AMOUNT,
    (
        PAYLOAD:billed_amount::NUMBER(18,2)
        -
        PAYLOAD:copay_amount::NUMBER(18,2)
    ) AS NET_PAYABLE_AMOUNT,
    PAYLOAD:status::VARCHAR AS STATUS
FROM
  (
    SELECT
        PAYLOAD,
        ROW_NUMBER() OVER
        (
            PARTITION BY PAYLOAD:claim_id::VARCHAR
            ORDER BY INGEST_ID DESC
        ) AS RN
    FROM STRM_BRONZE_CLAIMS
)
WHERE RN = 1;  

SELECT *
FROM SILVER_CLAIMS_TRANSACTIONS
ORDER BY CLAIM_ID;

SELECT *
FROM STRM_BRONZE_CLAIMS;

DROP STREAM IF EXISTS STRM_BRONZE_CLAIMS;

--=======================TASK 4=================================================

CREATE OR REPLACE DYNAMIC TABLE DT_PROVIDER_FINANCIAL_SUMMARY
(
    PROVIDER_ID,
    TOTAL_BILLED_AMOUNT,
    TOTAL_COPAY_COLLECT,
    TOTAL_NET_PAYABLE,
    APPROVED_CLAIMS
)
TARGET_LAG = '1 minute'
WAREHOUSE = P16_WH
AS
SELECT
    PROVIDER_ID,
    SUM(BILLED_AMOUNT) AS TOTAL_BILLED_AMOUNT,
    SUM(COPAY_AMOUNT) AS TOTAL_COPAY_COLLECT,
    SUM(NET_PAYABLE_AMOUNT) AS TOTAL_NET_PAYABLE,
    COUNT(*) AS APPROVED_CLAIMS
FROM SILVER_CLAIMS_TRANSACTIONS
WHERE STATUS = 'APPROVED'
GROUP BY PROVIDER_ID;

SELECT *
FROM DT_PROVIDER_FINANCIAL_SUMMARY
ORDER BY PROVIDER_ID;

--=====================TASK 5============================
SELECT *
FROM TABLE
(
    INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY
(
    NAME => 'DT_PROVIDER_FINANCIAL_SUMMARY',
    RESULT_LIMIT => 20
)
)
ORDER BY REFRESH_START_TIME DESC;


--=================TASK 6======================
SELECT
    (
        SELECT SUM(PAYLOAD:billed_amount::NUMBER(18,2))
        FROM BRONZE_RAW_CLAIMS
    ) AS BRONZE_GROSS_TOTAL,

    (
        SELECT SUM(BILLED_AMOUNT)
        FROM SILVER_CLAIMS_TRANSACTIONS
    ) AS SILVER_GROSS_TOTAL,

    (
        SELECT SUM(TOTAL_BILLED_AMOUNT)
        FROM DT_PROVIDER_FINANCIAL_SUMMARY
    ) AS GOLD_GROSS_TOTAL,

    CASE
        WHEN
            (
                SELECT SUM(PAYLOAD:billed_amount::NUMBER(18,2))
                FROM BRONZE_RAW_CLAIMS
            ) = 250700.00

            AND

            (
                SELECT SUM(BILLED_AMOUNT)
                FROM SILVER_CLAIMS_TRANSACTIONS
            ) = 197700.00

            AND

            (
                SELECT SUM(TOTAL_BILLED_AMOUNT)
                FROM DT_PROVIDER_FINANCIAL_SUMMARY
            ) = 152700.00

        THEN TRUE
        ELSE FALSE
    END AS RECONCILED_FLAG;