-- ============================================================
-- 01. STAGING TABLE CREATION & CSV INGESTION
-- Database: lending_club_db (MySQL 8.0+)
-- ============================================================

CREATE DATABASE IF NOT EXISTS lending_club_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE lending_club_db;

SET GLOBAL local_infile = 1;

CREATE TABLE IF NOT EXISTS stg_accepted_loans (
    id VARCHAR(30),
    loan_amnt VARCHAR(30),
    term VARCHAR(20),
    int_rate VARCHAR(30),
    grade VARCHAR(10),
    emp_length VARCHAR(30),
    home_ownership VARCHAR(30),
    annual_inc VARCHAR(30),
    verification_status VARCHAR(50),
    issue_d VARCHAR(30),
    purpose VARCHAR(50),
    addr_state VARCHAR(10),
    dti VARCHAR(30),
    delinq_2yrs VARCHAR(30),
    fico_range_low VARCHAR(30),
    revol_util VARCHAR(30),
    credit_policy_flag VARCHAR(10),
    loan_status_clean VARCHAR(50),
    dti_999_flag VARCHAR(10),
    revol_util_over_100_flag VARCHAR(10),
    revol_util_over_200_flag VARCHAR(10)
);

-- Update path below to the absolute path of your local 'data/cleaned/accepted_loans_cleaned.csv'
LOAD DATA LOCAL INFILE
'data/cleaned/accepted_loans_cleaned.csv'
INTO TABLE stg_accepted_loans
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    id,
    loan_amnt,
    term,
    int_rate,
    grade,
    emp_length,
    home_ownership,
    annual_inc,
    verification_status,
    issue_d,
    purpose,
    addr_state,
    dti,
    delinq_2yrs,
    fico_range_low,
    revol_util,
    credit_policy_flag,
    loan_status_clean,
    dti_999_flag,
    revol_util_over_100_flag,
    revol_util_over_200_flag
);


-- ============================================================
-- STAGING DATA QUALITY CHECKS
-- ============================================================

SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT id) AS unique_ids
FROM stg_accepted_loans;

SELECT
    id,
    COUNT(id) AS duplicate_id_count
FROM stg_accepted_loans
GROUP BY id
HAVING COUNT(id) > 1;

SELECT
    SUM(id IS NULL OR id = '') AS missing_id,
    SUM(loan_amnt IS NULL OR loan_amnt = '') AS missing_loan_amnt,
    SUM(term IS NULL OR term = '') AS missing_term,
    SUM(grade IS NULL OR grade = '') AS missing_grade,
    SUM(loan_status_clean IS NULL OR loan_status_clean = '') AS missing_loan_status,
    SUM(issue_d IS NULL OR issue_d = '') AS missing_issue_date
FROM stg_accepted_loans;

SELECT
    loan_status_clean,
    COUNT(*) AS total_loans
FROM stg_accepted_loans
GROUP BY loan_status_clean
ORDER BY total_loans DESC;

SELECT *
FROM stg_accepted_loans
LIMIT 15;