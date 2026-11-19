-- ============================================================
-- 02. LENDING CLUB END-TO-END STAR SCHEMA & BATCH ETL PIPELINE
-- Database: lending_club_db (MySQL 8.0+)
-- ============================================================

CREATE DATABASE IF NOT EXISTS lending_club_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE lending_club_db;


-- ============================================================
-- PART 1: SESSION & SERVER CONFIGURATION
-- ============================================================

SET GLOBAL local_infile = 1;
SET SESSION wait_timeout = 28800;
SET SESSION interactive_timeout = 28800;
SET SESSION net_read_timeout = 600;
SET SESSION net_write_timeout = 600;
SET SESSION innodb_lock_wait_timeout = 300;


-- ============================================================
-- PART 2: CLEAN RESET (SAFE RE-RUNS)
-- ============================================================

DROP PROCEDURE IF EXISTS load_fact_loan_batches;
DROP TABLE IF EXISTS fact_load_control;
DROP TABLE IF EXISTS fact_loan;
DROP TABLE IF EXISTS dim_borrower_profile;
DROP TABLE IF EXISTS dim_loan_characteristics;
DROP TABLE IF EXISTS dim_loan_status;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS stg_accepted_loans;


-- ============================================================
-- PART 3: CREATE & LOAD STAGING TABLE
-- (Exact 21 columns produced by scripts/clean_lending_club.py)
-- ============================================================

CREATE TABLE stg_accepted_loans (
    id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    loan_amnt VARCHAR(30),
    term VARCHAR(30),
    int_rate VARCHAR(30),
    grade VARCHAR(20),
    emp_length VARCHAR(30),
    home_ownership VARCHAR(30),
    annual_inc VARCHAR(30),
    verification_status VARCHAR(50),
    issue_d VARCHAR(30),
    purpose VARCHAR(100),
    addr_state VARCHAR(20),
    dti VARCHAR(30),
    delinq_2yrs VARCHAR(30),
    fico_range_low VARCHAR(30),
    revol_util VARCHAR(30),
    credit_policy_flag VARCHAR(15),
    loan_status_clean VARCHAR(100),
    dti_999_flag VARCHAR(15),
    revol_util_over_100_flag VARCHAR(15),
    revol_util_over_200_flag VARCHAR(15)
) ENGINE = InnoDB;

-- Update path below to the absolute path of your local 'data/cleaned/accepted_loans_cleaned.csv'
LOAD DATA LOCAL INFILE
'data/cleaned/accepted_loans_cleaned.csv'
INTO TABLE stg_accepted_loans
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
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
-- PART 4: CREATE DIMENSION TABLES
-- ============================================================

-- 1. DATE DIMENSION
CREATE TABLE dim_date (
    date_key INT NOT NULL PRIMARY KEY,
    full_date DATE NOT NULL,
    year SMALLINT,
    quarter TINYINT,
    month TINYINT,
    month_name VARCHAR(15),
    UNIQUE KEY uk_dim_date_full_date (full_date)
) ENGINE = InnoDB;


-- 2. LOAN STATUS DIMENSION
CREATE TABLE dim_loan_status (
    status_key INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    loan_status VARCHAR(50) NOT NULL,
    UNIQUE KEY uk_loan_status (loan_status)
) ENGINE = InnoDB;


-- 3. LOAN CHARACTERISTICS DIMENSION
CREATE TABLE dim_loan_characteristics (
    loan_characteristics_key INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    term_months SMALLINT,
    grade VARCHAR(10),
    purpose VARCHAR(100),
    verification_status VARCHAR(50),
    credit_policy_flag TINYINT,
    INDEX idx_lc_lookup (
        term_months,
        grade,
        purpose,
        verification_status,
        credit_policy_flag
    )
) ENGINE = InnoDB;


-- 4. BORROWER PROFILE DIMENSION
CREATE TABLE dim_borrower_profile (
    borrower_profile_key INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    emp_length VARCHAR(30),
    home_ownership VARCHAR(50),
    addr_state VARCHAR(10),
    INDEX idx_borrower_lookup (
        emp_length,
        home_ownership,
        addr_state
    )
) ENGINE = InnoDB;


-- ============================================================
-- PART 5: CREATE FACT TABLE
-- ============================================================

CREATE TABLE fact_loan (
    loan_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,

    date_key INT NOT NULL,
    status_key INT UNSIGNED,
    loan_characteristics_key INT UNSIGNED,
    borrower_profile_key INT UNSIGNED,

    -- Loan measures
    loan_amnt DECIMAL(12,2),
    int_rate DECIMAL(7,4),
    annual_inc DECIMAL(15,2),
    dti DECIMAL(10,4),
    delinq_2yrs INT,
    fico_range_low SMALLINT,
    revol_util DECIMAL(10,4),

    -- Data quality flags
    dti_999_flag TINYINT,
    revol_util_over_100_flag TINYINT,
    revol_util_over_200_flag TINYINT,

    -- Loan outcome flags
    default_flag TINYINT,
    outcome_eligible_flag TINYINT,

    -- Foreign keys
    CONSTRAINT fk_fact_date
        FOREIGN KEY (date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT fk_fact_status
        FOREIGN KEY (status_key)
        REFERENCES dim_loan_status(status_key),

    CONSTRAINT fk_fact_characteristics
        FOREIGN KEY (loan_characteristics_key)
        REFERENCES dim_loan_characteristics(loan_characteristics_key),

    CONSTRAINT fk_fact_borrower
        FOREIGN KEY (borrower_profile_key)
        REFERENCES dim_borrower_profile(borrower_profile_key),

    INDEX idx_fact_date (date_key),
    INDEX idx_fact_status (status_key),
    INDEX idx_fact_characteristics (loan_characteristics_key),
    INDEX idx_fact_borrower (borrower_profile_key)
) ENGINE = InnoDB;


-- ============================================================
-- PART 6: POPULATE DIMENSION TABLES
-- ============================================================

-- 1. POPULATE DATE DIMENSION
INSERT INTO dim_date (
    date_key,
    full_date,
    year,
    quarter,
    month,
    month_name
)
SELECT DISTINCT
    CAST(DATE_FORMAT(x.issue_date, '%Y%m%d') AS UNSIGNED),
    x.issue_date,
    YEAR(x.issue_date),
    QUARTER(x.issue_date),
    MONTH(x.issue_date),
    MONTHNAME(x.issue_date)
FROM (
    SELECT
        STR_TO_DATE(NULLIF(TRIM(BOTH '\r' FROM TRIM(issue_d)), ''), '%Y-%m-%d') AS issue_date
    FROM stg_accepted_loans
) x
WHERE x.issue_date IS NOT NULL;


-- 2. POPULATE LOAN STATUS DIMENSION
INSERT INTO dim_loan_status (loan_status)
SELECT DISTINCT
    COALESCE(NULLIF(TRIM(BOTH '\r' FROM TRIM(loan_status_clean)), ''), 'Unknown')
FROM stg_accepted_loans;


-- 3. POPULATE LOAN CHARACTERISTICS DIMENSION
INSERT INTO dim_loan_characteristics (
    term_months,
    grade,
    purpose,
    verification_status,
    credit_policy_flag
)
SELECT DISTINCT
    CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(term)), '') AS UNSIGNED) AS term_months,
    NULLIF(TRIM(BOTH '\r' FROM TRIM(grade)), '') AS grade,
    NULLIF(TRIM(BOTH '\r' FROM TRIM(purpose)), '') AS purpose,
    NULLIF(TRIM(BOTH '\r' FROM TRIM(verification_status)), '') AS verification_status,
    CASE
        WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(credit_policy_flag))) IN ('true', '1') THEN 1
        WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(credit_policy_flag))) IN ('false', '0') THEN 0
        ELSE NULL
    END AS credit_policy_flag
FROM stg_accepted_loans;


-- 4. POPULATE BORROWER PROFILE DIMENSION
INSERT INTO dim_borrower_profile (
    emp_length,
    home_ownership,
    addr_state
)
SELECT DISTINCT
    NULLIF(TRIM(BOTH '\r' FROM TRIM(emp_length)), ''),
    NULLIF(TRIM(BOTH '\r' FROM TRIM(home_ownership)), ''),
    NULLIF(TRIM(BOTH '\r' FROM TRIM(addr_state)), '')
FROM stg_accepted_loans;


-- ============================================================
-- PART 7: CREATE FACT LOAD CHECKPOINT TABLE
-- ============================================================

CREATE TABLE fact_load_control (
    process_id INT NOT NULL PRIMARY KEY,
    last_loan_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
    total_loaded BIGINT NOT NULL DEFAULT 0,
    last_batch_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP
) ENGINE = InnoDB;

INSERT INTO fact_load_control (
    process_id,
    last_loan_id,
    total_loaded,
    last_batch_count
)
VALUES (1, 0, 0, 0);


-- ============================================================
-- PART 8: CREATE OPTIMIZED BATCH LOADING PROCEDURE
-- ============================================================

DELIMITER $$

CREATE PROCEDURE load_fact_loan_batches(
    IN p_batch_size INT
)
BEGIN
    DECLARE v_last_id BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_batch_max BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_batch_count INT DEFAULT 0;
    DECLARE v_inserted INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_fact_batch;
        RESIGNAL;
    END;

    -- Read checkpoint
    SELECT last_loan_id
    INTO v_last_id
    FROM fact_load_control
    WHERE process_id = 1;

    -- Create temporary batch table
    CREATE TEMPORARY TABLE tmp_fact_batch (
        id BIGINT UNSIGNED NOT NULL PRIMARY KEY
    ) ENGINE = InnoDB;

    batch_loop: LOOP

        START TRANSACTION;

        TRUNCATE TABLE tmp_fact_batch;

        -- Fast primary-key range scan on stg_accepted_loans.id
        INSERT INTO tmp_fact_batch (id)
        SELECT id
        FROM stg_accepted_loans
        WHERE id > v_last_id
        ORDER BY id
        LIMIT p_batch_size;

        SELECT
            COUNT(*),
            MAX(id)
        INTO
            v_batch_count,
            v_batch_max
        FROM tmp_fact_batch;

        -- Stop when no more rows
        IF v_batch_count = 0 THEN
            COMMIT;
            LEAVE batch_loop;
        END IF;

        -- Insert batch into fact_loan
        INSERT INTO fact_loan (
            loan_id,
            date_key,
            status_key,
            loan_characteristics_key,
            borrower_profile_key,

            loan_amnt,
            int_rate,
            annual_inc,
            dti,
            delinq_2yrs,
            fico_range_low,
            revol_util,

            dti_999_flag,
            revol_util_over_100_flag,
            revol_util_over_200_flag,

            default_flag,
            outcome_eligible_flag
        )
        SELECT
            s.id,
            d.date_key,
            st.status_key,
            lc.loan_characteristics_key,
            bp.borrower_profile_key,

            CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.loan_amnt)), '') AS DECIMAL(12,2)),
            CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.int_rate)), '') AS DECIMAL(7,4)),
            CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.annual_inc)), '') AS DECIMAL(15,2)),
            CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.dti)), '') AS DECIMAL(10,4)),
            CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.delinq_2yrs)), '') AS SIGNED),
            CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.fico_range_low)), '') AS UNSIGNED),
            CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.revol_util)), '') AS DECIMAL(10,4)),

            -- Data quality flags
            CASE
                WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.dti_999_flag))) IN ('true', '1') THEN 1
                WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.dti_999_flag))) IN ('false', '0') THEN 0
                ELSE NULL
            END,

            CASE
                WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.revol_util_over_100_flag))) IN ('true', '1') THEN 1
                WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.revol_util_over_100_flag))) IN ('false', '0') THEN 0
                ELSE NULL
            END,

            CASE
                WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.revol_util_over_200_flag))) IN ('true', '1') THEN 1
                WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.revol_util_over_200_flag))) IN ('false', '0') THEN 0
                ELSE NULL
            END,

            -- Default flag
            CASE
                WHEN TRIM(BOTH '\r' FROM TRIM(s.loan_status_clean)) IN ('Charged Off', 'Default') THEN 1
                WHEN TRIM(BOTH '\r' FROM TRIM(s.loan_status_clean)) = 'Fully Paid' THEN 0
                ELSE NULL
            END,

            -- Outcome eligibility flag
            CASE
                WHEN TRIM(BOTH '\r' FROM TRIM(s.loan_status_clean)) IN ('Fully Paid', 'Charged Off', 'Default') THEN 1
                ELSE 0
            END

        FROM tmp_fact_batch b

        INNER JOIN stg_accepted_loans s
            ON s.id = b.id

        INNER JOIN dim_date d
            ON d.full_date = STR_TO_DATE(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.issue_d)), ''), '%Y-%m-%d')

        INNER JOIN dim_loan_status st
            ON st.loan_status = COALESCE(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.loan_status_clean)), ''), 'Unknown')

        INNER JOIN dim_loan_characteristics lc
            ON lc.term_months <=> CAST(NULLIF(TRIM(BOTH '\r' FROM TRIM(s.term)), '') AS UNSIGNED)
           AND lc.grade <=> NULLIF(TRIM(BOTH '\r' FROM TRIM(s.grade)), '')
           AND lc.purpose <=> NULLIF(TRIM(BOTH '\r' FROM TRIM(s.purpose)), '')
           AND lc.verification_status <=> NULLIF(TRIM(BOTH '\r' FROM TRIM(s.verification_status)), '')
           AND lc.credit_policy_flag <=>
               CASE
                   WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.credit_policy_flag))) IN ('true', '1') THEN 1
                   WHEN LOWER(TRIM(BOTH '\r' FROM TRIM(s.credit_policy_flag))) IN ('false', '0') THEN 0
                   ELSE NULL
               END

        INNER JOIN dim_borrower_profile bp
            ON bp.emp_length <=> NULLIF(TRIM(BOTH '\r' FROM TRIM(s.emp_length)), '')
           AND bp.home_ownership <=> NULLIF(TRIM(BOTH '\r' FROM TRIM(s.home_ownership)), '')
           AND bp.addr_state <=> NULLIF(TRIM(BOTH '\r' FROM TRIM(s.addr_state)), '');

        -- Capture inserted row count
        SET v_inserted = ROW_COUNT();

        -- Ensure all selected rows were inserted
        IF v_inserted <> v_batch_count THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Fact batch count mismatch. Check dimension mappings.';
        END IF;

        -- Update checkpoint
        UPDATE fact_load_control
        SET
            last_loan_id = v_batch_max,
            total_loaded = total_loaded + v_inserted,
            last_batch_count = v_inserted
        WHERE process_id = 1;

        SET v_last_id = v_batch_max;

        COMMIT;

    END LOOP;

    DROP TEMPORARY TABLE IF EXISTS tmp_fact_batch;

    SELECT *
    FROM fact_load_control
    WHERE process_id = 1;

END$$

DELIMITER ;


-- ============================================================
-- PART 9: RUN FACT TABLE LOADING
-- ============================================================

CALL load_fact_loan_batches(50000);


-- ============================================================
-- PART 10: VALIDATE LOADED DATA
-- ============================================================

-- 1. Total rows in staging vs. fact table
SELECT
    (SELECT COUNT(*) FROM stg_accepted_loans) AS staging_rows,
    (SELECT COUNT(*) FROM fact_loan) AS fact_rows;

-- 2. Checkpoint information
SELECT *
FROM fact_load_control;

-- 3. Dimension table row counts
SELECT 'dim_date' AS table_name, COUNT(*) AS total_rows FROM dim_date
UNION ALL
SELECT 'dim_loan_status', COUNT(*) FROM dim_loan_status
UNION ALL
SELECT 'dim_loan_characteristics', COUNT(*) FROM dim_loan_characteristics
UNION ALL
SELECT 'dim_borrower_profile', COUNT(*) FROM dim_borrower_profile;

-- 4. Check duplicate loan IDs in fact table
SELECT
    COUNT(*) AS total_fact_rows,
    COUNT(DISTINCT loan_id) AS distinct_loan_ids
FROM fact_loan;

-- 5. Check loan outcome and quality flag distribution
SELECT
    st.loan_status,
    COUNT(*) AS loan_count,
    SUM(f.default_flag = 1) AS default_count,
    SUM(f.default_flag = 0) AS fully_paid_count,
    SUM(f.dti_999_flag = 1) AS dti_999_count,
    SUM(f.revol_util_over_100_flag = 1) AS revol_over_100_count,
    SUM(f.revol_util_over_200_flag = 1) AS revol_over_200_count
FROM fact_loan f
LEFT JOIN dim_loan_status st
    ON f.status_key = st.status_key
GROUP BY st.loan_status
ORDER BY loan_count DESC;

-- 6. Check unmatched / missing foreign keys
SELECT
    SUM(date_key IS NULL) AS missing_date_keys,
    SUM(status_key IS NULL) AS missing_status_keys,
    SUM(loan_characteristics_key IS NULL) AS missing_characteristics_keys,
    SUM(borrower_profile_key IS NULL) AS missing_borrower_keys
FROM fact_loan;