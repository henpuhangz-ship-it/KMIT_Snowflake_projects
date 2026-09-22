-- ============================================================================
-- PROJECT 13B: Healthcare Analytics Warehouse
-- Star Schema vs. Snowflake Schema
-- Technology: Snowflake SQL
-- ============================================================================


-- ============================================================================
-- ENVIRONMENT SETUP
-- ============================================================================

CREATE WAREHOUSE P13_HEALTHCARE_WH
    WAREHOUSE_SIZE = 'XSMALL';
USE WAREHOUSE P13_HEALTHCARE_WH;

CREATE DATABASE HEALTHCARE_DW;
USE DATABASE HEALTHCARE_DW;

CREATE SCHEMA HEALTHCARE_DW.SCHEMA_COMPARE_LAB;
USE SCHEMA SCHEMA_COMPARE_LAB;

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE           = 'CSV'
    SKIP_HEADER    = 1
    FIELD_DELIMITER = ','
    FIELD_OPTIONALLY_ENCLOSED_BY = '"';

CREATE OR REPLACE STAGE P13_HEALTHCARE_STAGE
    FILE_FORMAT = CSV_FORMAT;

LIST @P13_HEALTHCARE_STAGE;
SHOW STAGES IN SCHEMA HEALTHCARE_DW.SCHEMA_COMPARE_LAB;


-- ============================================================================
-- TASK 1 — CREATE ENVIRONMENT CONTEXT
-- ============================================================================
-- Already handled above. Verified via:
--   Current database : HEALTHCARE_DW
--   Current schema   : SCHEMA_COMPARE_LAB
-- ============================================================================


-- ============================================================================
-- TASK 2 — BUILD STAR SCHEMA HOSPITAL DIMENSION (STAR_DIM_HOSPITAL)
-- Denormalized: hospital + network name + network director in one flat table.
-- ============================================================================

CREATE TABLE STAR_DIM_HOSPITAL
(
    HOSPITAL_KEY      NUMBER        AUTOINCREMENT PRIMARY KEY,
    HOSPITAL_ID       NUMBER,
    HOSPITAL_NAME     VARCHAR(100),
    CITY              VARCHAR(50),
    STATE             VARCHAR(50),
    NETWORK_NAME      VARCHAR(100),
    NETWORK_DIRECTOR  VARCHAR(100)
);


-- ============================================================================
-- TASK 3 — BUILD STAR SCHEMA TREATMENT DIMENSION (STAR_DIM_TREATMENT)
-- Denormalized: treatment + diagnosis group name in one flat table.
-- ============================================================================

CREATE TABLE STAR_DIM_TREATMENT
(
    TREATMENT_KEY         NUMBER        AUTOINCREMENT PRIMARY KEY,
    TREATMENT_ID          NUMBER,
    TREATMENT_NAME        VARCHAR(100),
    DIAGNOSIS_GROUP_NAME  VARCHAR(50),
    STANDARD_COST         NUMBER(12,2)
);


-- ============================================================================
-- TASK 4 — LOAD STAR SCHEMA DIMENSION DATA
-- ============================================================================

-- 4.1  Load STAR_DIM_HOSPITAL from hospital_hierarchy.csv
--      Columns: hospital_id, hospital_name, city, state,
--               network_id, network_name, network_director

INSERT INTO STAR_DIM_HOSPITAL
(
    HOSPITAL_ID,
    HOSPITAL_NAME,
    CITY,
    STATE,
    NETWORK_NAME,
    NETWORK_DIRECTOR
)
SELECT
    $1,   -- hospital_id
    $2,   -- hospital_name
    $3,   -- city
    $4,   -- state
    $6,   -- network_name
    $7    -- network_director
FROM @P13_HEALTHCARE_STAGE/hospital_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);

-- 4.2  Load STAR_DIM_TREATMENT from treatment_hierarchy.csv
--      Columns: treatment_id, treatment_name, diagnosis_group_id,
--               diagnosis_group_name, standard_cost

INSERT INTO STAR_DIM_TREATMENT
(
    TREATMENT_ID,
    TREATMENT_NAME,
    DIAGNOSIS_GROUP_NAME,
    STANDARD_COST
)
SELECT
    $1,   -- treatment_id
    $2,   -- treatment_name
    $4,   -- diagnosis_group_name
    $5    -- standard_cost
FROM @P13_HEALTHCARE_STAGE/treatment_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);


-- ============================================================================
-- TASK 5 — BUILD & LOAD STAR SCHEMA FACT TABLE (STAR_FACT_CLAIMS)
-- ============================================================================

CREATE TABLE STAR_FACT_CLAIMS
(
    CLAIM_KEY        NUMBER        AUTOINCREMENT PRIMARY KEY,
    CLAIM_ID         VARCHAR(50),
    CLAIM_DATE       DATE,
    PATIENT_ID       NUMBER,
    HOSPITAL_KEY     NUMBER,
    TREATMENT_KEY    NUMBER,
    CLAIMED_AMOUNT   NUMBER(12,2),
    APPROVED_AMOUNT  NUMBER(12,2),

    CONSTRAINT FK_STAR_HOSPITAL
        FOREIGN KEY (HOSPITAL_KEY)
        REFERENCES STAR_DIM_HOSPITAL(HOSPITAL_KEY),

    CONSTRAINT FK_STAR_TREATMENT
        FOREIGN KEY (TREATMENT_KEY)
        REFERENCES STAR_DIM_TREATMENT(TREATMENT_KEY)
);

-- Load STAR_FACT_CLAIMS from insurance_claims.csv
-- Columns: claim_id, claim_date, patient_id, hospital_id,
--          treatment_id, claimed_amount, approved_amount

INSERT INTO STAR_FACT_CLAIMS
(
    CLAIM_ID,
    CLAIM_DATE,
    PATIENT_ID,
    HOSPITAL_KEY,
    TREATMENT_KEY,
    CLAIMED_AMOUNT,
    APPROVED_AMOUNT
)
SELECT
    C.$1,             -- claim_id
    C.$2::DATE,       -- claim_date
    C.$3,             -- patient_id
    H.HOSPITAL_KEY,   -- resolved surrogate key
    T.TREATMENT_KEY,  -- resolved surrogate key
    C.$6,             -- claimed_amount
    C.$7              -- approved_amount
FROM @P13_HEALTHCARE_STAGE/insurance_claims.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) C
JOIN STAR_DIM_HOSPITAL  H ON C.$4 = H.HOSPITAL_ID
JOIN STAR_DIM_TREATMENT T ON C.$5 = T.TREATMENT_ID;


-- ============================================================================
-- TASK 6 — BUILD SNOWFLAKE SCHEMA HOSPITAL HIERARCHY
-- Normalized: SNOW_DIM_NETWORK  ->  SNOW_DIM_HOSPITAL
-- ============================================================================

CREATE TABLE SNOW_DIM_NETWORK
(
    NETWORK_KEY       NUMBER        AUTOINCREMENT PRIMARY KEY,
    NETWORK_ID        NUMBER,
    NETWORK_NAME      VARCHAR(100),
    NETWORK_DIRECTOR  VARCHAR(100)
);

CREATE TABLE SNOW_DIM_HOSPITAL
(
    HOSPITAL_KEY   NUMBER        AUTOINCREMENT PRIMARY KEY,
    HOSPITAL_ID    NUMBER,
    HOSPITAL_NAME  VARCHAR(100),
    CITY           VARCHAR(50),
    STATE          VARCHAR(50),
    NETWORK_KEY    NUMBER,

    CONSTRAINT FK_SNOW_HOSPITAL_NETWORK
        FOREIGN KEY (NETWORK_KEY)
        REFERENCES SNOW_DIM_NETWORK(NETWORK_KEY)
);


-- ============================================================================
-- TASK 7 — BUILD SNOWFLAKE SCHEMA TREATMENT HIERARCHY
-- Normalized: SNOW_DIM_DIAGNOSIS_GROUP  ->  SNOW_DIM_TREATMENT
-- ============================================================================

CREATE TABLE SNOW_DIM_DIAGNOSIS_GROUP
(
    DIAGNOSIS_GROUP_KEY   NUMBER        AUTOINCREMENT PRIMARY KEY,
    DIAGNOSIS_GROUP_ID    VARCHAR(20),
    DIAGNOSIS_GROUP_NAME  VARCHAR(50)
);

CREATE TABLE SNOW_DIM_TREATMENT
(
    TREATMENT_KEY         NUMBER        AUTOINCREMENT PRIMARY KEY,
    TREATMENT_ID          NUMBER,
    TREATMENT_NAME        VARCHAR(100),
    STANDARD_COST         NUMBER(12,2),
    DIAGNOSIS_GROUP_KEY   NUMBER,

    CONSTRAINT FK_SNOW_TREATMENT_DIAGGROUP
        FOREIGN KEY (DIAGNOSIS_GROUP_KEY)
        REFERENCES SNOW_DIM_DIAGNOSIS_GROUP(DIAGNOSIS_GROUP_KEY)
);


-- ============================================================================
-- TASK 8 — POPULATE SNOWFLAKE SCHEMA NORMALIZED HIERARCHIES
-- ============================================================================

-- 8.1  Load SNOW_DIM_NETWORK
--      Source: hospital_hierarchy.csv ($5=network_id, $6=network_name, $7=network_director)
--      One row per distinct network (DISTINCT on network_id eliminates hospital duplicates).

INSERT INTO SNOW_DIM_NETWORK
(
    NETWORK_ID,
    NETWORK_NAME,
    NETWORK_DIRECTOR
)
SELECT DISTINCT
    $5,   -- network_id
    $6,   -- network_name
    $7    -- network_director
FROM @P13_HEALTHCARE_STAGE/hospital_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);


-- 8.2  Load SNOW_DIM_HOSPITAL
--      JOIN to SNOW_DIM_NETWORK on network_name to resolve NETWORK_KEY.

INSERT INTO SNOW_DIM_HOSPITAL
(
    HOSPITAL_ID,
    HOSPITAL_NAME,
    CITY,
    STATE,
    NETWORK_KEY
)
SELECT
    H.$1,             -- hospital_id
    H.$2,             -- hospital_name
    H.$3,             -- city
    H.$4,             -- state
    N.NETWORK_KEY     -- resolved surrogate key
FROM @P13_HEALTHCARE_STAGE/hospital_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) H
JOIN SNOW_DIM_NETWORK N
    ON H.$6 = N.NETWORK_NAME;


-- 8.3  Load SNOW_DIM_DIAGNOSIS_GROUP
--      Source: treatment_hierarchy.csv ($3=diagnosis_group_id, $4=diagnosis_group_name)

INSERT INTO SNOW_DIM_DIAGNOSIS_GROUP
(
    DIAGNOSIS_GROUP_ID,
    DIAGNOSIS_GROUP_NAME
)
SELECT DISTINCT
    $3,   -- diagnosis_group_id   (e.g. DG-CARD)
    $4    -- diagnosis_group_name (e.g. Cardiology)
FROM @P13_HEALTHCARE_STAGE/treatment_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
);


-- 8.4  Load SNOW_DIM_TREATMENT
--      JOIN to SNOW_DIM_DIAGNOSIS_GROUP on diagnosis_group_name to resolve key.

INSERT INTO SNOW_DIM_TREATMENT
(
    TREATMENT_ID,
    TREATMENT_NAME,
    STANDARD_COST,
    DIAGNOSIS_GROUP_KEY
)
SELECT
    T.$1,                    -- treatment_id
    T.$2,                    -- treatment_name
    T.$5,                    -- standard_cost
    DG.DIAGNOSIS_GROUP_KEY   -- resolved surrogate key
FROM @P13_HEALTHCARE_STAGE/treatment_hierarchy.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) T
JOIN SNOW_DIM_DIAGNOSIS_GROUP DG
    ON T.$4 = DG.DIAGNOSIS_GROUP_NAME;


-- Optional verification selects for Task 8
SELECT * FROM SNOW_DIM_NETWORK;
SELECT * FROM SNOW_DIM_HOSPITAL;
SELECT * FROM SNOW_DIM_DIAGNOSIS_GROUP;
SELECT * FROM SNOW_DIM_TREATMENT;


-- ============================================================================
-- TASK 9 — BUILD & LOAD SNOWFLAKE SCHEMA FACT TABLE (SNOW_FACT_CLAIMS)
-- ============================================================================

CREATE TABLE SNOW_FACT_CLAIMS
(
    CLAIM_KEY        NUMBER        AUTOINCREMENT PRIMARY KEY,
    CLAIM_ID         VARCHAR(50),
    CLAIM_DATE       DATE,
    PATIENT_ID       NUMBER,
    HOSPITAL_KEY     NUMBER,
    TREATMENT_KEY    NUMBER,
    CLAIMED_AMOUNT   NUMBER(12,2),
    APPROVED_AMOUNT  NUMBER(12,2),

    CONSTRAINT FK_SNOW_FACT_HOSPITAL
        FOREIGN KEY (HOSPITAL_KEY)
        REFERENCES SNOW_DIM_HOSPITAL(HOSPITAL_KEY),

    CONSTRAINT FK_SNOW_FACT_TREATMENT
        FOREIGN KEY (TREATMENT_KEY)
        REFERENCES SNOW_DIM_TREATMENT(TREATMENT_KEY)
);

-- Load SNOW_FACT_CLAIMS from insurance_claims.csv

INSERT INTO SNOW_FACT_CLAIMS
(
    CLAIM_ID,
    CLAIM_DATE,
    PATIENT_ID,
    HOSPITAL_KEY,
    TREATMENT_KEY,
    CLAIMED_AMOUNT,
    APPROVED_AMOUNT
)
SELECT
    C.$1,             -- claim_id
    C.$2::DATE,       -- claim_date
    C.$3,             -- patient_id
    H.HOSPITAL_KEY,   -- resolved surrogate key
    T.TREATMENT_KEY,  -- resolved surrogate key
    C.$6,             -- claimed_amount
    C.$7              -- approved_amount
FROM @P13_HEALTHCARE_STAGE/insurance_claims.csv
(
    FILE_FORMAT => 'CSV_FORMAT'
) C
JOIN SNOW_DIM_HOSPITAL  H ON C.$4 = H.HOSPITAL_ID
JOIN SNOW_DIM_TREATMENT T ON C.$5 = T.TREATMENT_ID;


-- ============================================================================
-- TASK 10 — STAR SCHEMA SPECIALTY CLAIMS ANALYSIS (Flat 1-Hop Query)
-- Total Claimed & Approved Amount grouped by Diagnosis Group Name.
-- Only 2 JOINs required — everything lives flat in STAR_DIM_TREATMENT.
-- ============================================================================

SELECT
    T.DIAGNOSIS_GROUP_NAME,
    SUM(F.CLAIMED_AMOUNT)  AS TOTAL_CLAIMED_AMOUNT,
    SUM(F.APPROVED_AMOUNT) AS TOTAL_APPROVED_AMOUNT
FROM STAR_FACT_CLAIMS F
JOIN STAR_DIM_TREATMENT T
    ON F.TREATMENT_KEY = T.TREATMENT_KEY
GROUP BY
    T.DIAGNOSIS_GROUP_NAME
ORDER BY
    T.DIAGNOSIS_GROUP_NAME;


-- ============================================================================
-- TASK 11 — SNOWFLAKE SCHEMA SPECIALTY CLAIMS ANALYSIS (Multi-Hop Join Query)
-- Same financial summary, but must traverse the normalized hierarchy:
--   SNOW_FACT_CLAIMS -> SNOW_DIM_TREATMENT -> SNOW_DIM_DIAGNOSIS_GROUP
-- ============================================================================

SELECT
    DG.DIAGNOSIS_GROUP_NAME,
    SUM(F.CLAIMED_AMOUNT)  AS TOTAL_CLAIMED_AMOUNT,
    SUM(F.APPROVED_AMOUNT) AS TOTAL_APPROVED_AMOUNT
FROM SNOW_FACT_CLAIMS F

JOIN SNOW_DIM_TREATMENT T
    ON F.TREATMENT_KEY = T.TREATMENT_KEY

JOIN SNOW_DIM_DIAGNOSIS_GROUP DG
    ON T.DIAGNOSIS_GROUP_KEY = DG.DIAGNOSIS_GROUP_KEY

GROUP BY
    DG.DIAGNOSIS_GROUP_NAME
ORDER BY
    DG.DIAGNOSIS_GROUP_NAME;


-- ============================================================================
-- TASK 12 — HOSPITAL NETWORK DIRECTOR PERFORMANCE REPORT
-- Total claims handled and total approved amount per Network Director.
-- Query uses the Star Schema (single JOIN); Snowflake variant shown below.
-- ============================================================================

-- Star Schema version (1-hop, NETWORK_DIRECTOR lives in STAR_DIM_HOSPITAL)
SELECT
    H.NETWORK_DIRECTOR,
    COUNT(F.CLAIM_KEY)     AS TOTAL_CLAIMS_HANDLED,
    SUM(F.APPROVED_AMOUNT) AS TOTAL_APPROVED_AMOUNT
FROM STAR_FACT_CLAIMS F
JOIN STAR_DIM_HOSPITAL H
    ON F.HOSPITAL_KEY = H.HOSPITAL_KEY
GROUP BY
    H.NETWORK_DIRECTOR
ORDER BY
    H.NETWORK_DIRECTOR;

-- Snowflake Schema version (multi-hop: traverse SNOW_DIM_HOSPITAL -> SNOW_DIM_NETWORK)
SELECT
    N.NETWORK_DIRECTOR,
    COUNT(F.CLAIM_KEY)     AS TOTAL_CLAIMS_HANDLED,
    SUM(F.APPROVED_AMOUNT) AS TOTAL_APPROVED_AMOUNT
FROM SNOW_FACT_CLAIMS F

JOIN SNOW_DIM_HOSPITAL H
    ON F.HOSPITAL_KEY = H.HOSPITAL_KEY

JOIN SNOW_DIM_NETWORK N
    ON H.NETWORK_KEY = N.NETWORK_KEY

GROUP BY
    N.NETWORK_DIRECTOR
ORDER BY
    N.NETWORK_DIRECTOR;


-- ============================================================================
-- TASK 13 — DATA ANOMALY ANALYSIS: MASTER DATA UPDATE TEST
-- Replace Dr. Ramesh with Dr. Anand for Apollo Healthcare Group (Network 10).
-- Demonstrates update-effort difference between the two schema designs.
-- ============================================================================

-- Star Schema: NETWORK_DIRECTOR is repeated in every hospital row.
-- Apollo has 2 hospitals -> 2 rows must be updated.

UPDATE STAR_DIM_HOSPITAL
SET    NETWORK_DIRECTOR = 'Dr. Anand'
WHERE  NETWORK_NAME     = 'Apollo Healthcare Group';

-- Snowflake Schema: NETWORK_DIRECTOR lives only once in SNOW_DIM_NETWORK.
-- Apollo is 1 network row -> exactly 1 row updated regardless of hospital count.

UPDATE SNOW_DIM_NETWORK
SET    NETWORK_DIRECTOR = 'Dr. Anand'
WHERE  NETWORK_NAME     = 'Apollo Healthcare Group';

-- Verification: confirm the update effect in each schema

SELECT
    'Star Schema'        AS SCHEMA_TYPE,
    'STAR_DIM_HOSPITAL'  AS UPDATED_TABLE,
    COUNT(*)             AS ROWS_UPDATED,
    'Higher (Multiple rows)' AS MAINTENANCE_EFFORT
FROM STAR_DIM_HOSPITAL
WHERE NETWORK_DIRECTOR = 'Dr. Anand'

UNION ALL

SELECT
    'Snowflake Schema',
    'SNOW_DIM_NETWORK',
    COUNT(*),
    'Lower (Single row)'
FROM SNOW_DIM_NETWORK
WHERE NETWORK_DIRECTOR = 'Dr. Anand';


-- ============================================================================
-- TASK 14 — FULL ARCHITECTURE RECORD AUDIT & SCHEMA COMPARISON
-- UNION ALL across all Star and Snowflake tables to verify record counts.
-- ============================================================================

SELECT 'Star Schema'     AS SCHEMA_TYPE, 'STAR_DIM_HOSPITAL'        AS TABLE_NAME, COUNT(*) AS RECORD_COUNT FROM STAR_DIM_HOSPITAL
UNION ALL
SELECT 'Star Schema',                    'STAR_DIM_TREATMENT',                      COUNT(*) FROM STAR_DIM_TREATMENT
UNION ALL
SELECT 'Star Schema',                    'STAR_FACT_CLAIMS',                         COUNT(*) FROM STAR_FACT_CLAIMS
UNION ALL
SELECT 'Snowflake Schema',               'SNOW_DIM_NETWORK',                        COUNT(*) FROM SNOW_DIM_NETWORK
UNION ALL
SELECT 'Snowflake Schema',               'SNOW_DIM_HOSPITAL',                       COUNT(*) FROM SNOW_DIM_HOSPITAL
UNION ALL
SELECT 'Snowflake Schema',               'SNOW_DIM_DIAGNOSIS_GROUP',                COUNT(*) FROM SNOW_DIM_DIAGNOSIS_GROUP
UNION ALL
SELECT 'Snowflake Schema',               'SNOW_DIM_TREATMENT',                      COUNT(*) FROM SNOW_DIM_TREATMENT
UNION ALL
SELECT 'Snowflake Schema',               'SNOW_FACT_CLAIMS',                        COUNT(*) FROM SNOW_FACT_CLAIMS

ORDER BY SCHEMA_TYPE DESC, TABLE_NAME;
