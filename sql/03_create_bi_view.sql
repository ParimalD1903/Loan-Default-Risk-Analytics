-- ============================================================
-- 03. POWER BI ANALYTICAL VIEW (DERIVED SEGMENTS & POLICY FLAGS)
-- Database: lending_club_db (MySQL 8.0+)
-- ============================================================

USE lending_club_db;

CREATE OR REPLACE VIEW vw_fact_loan_bi AS
SELECT
    f.loan_id,
    f.date_key,
    f.status_key,
    f.loan_characteristics_key,
    f.borrower_profile_key,
    f.loan_amnt,
    f.int_rate,
    f.annual_inc,
    f.dti,
    f.delinq_2yrs,
    f.fico_range_low,
    f.revol_util,
    f.dti_999_flag,
    f.revol_util_over_100_flag,
    f.revol_util_over_200_flag,
    f.default_flag,
    f.outcome_eligible_flag,

    -- 1. Income Bracket (for Default Probability by Income)
    CASE
        WHEN f.annual_inc IS NULL THEN 'Unknown / Missing'
        WHEN f.annual_inc < 40000 THEN 'Low (< $40K)'
        WHEN f.annual_inc < 75000 THEN 'Lower-Middle ($40K - $75K)'
        WHEN f.annual_inc < 120000 THEN 'Upper-Middle ($75K - $120K)'
        ELSE 'High ($120K+)'
    END AS income_bracket,

    -- 2. Sort Order for Income Bracket in Power BI
    CASE
        WHEN f.annual_inc IS NULL THEN 5
        WHEN f.annual_inc < 40000 THEN 1
        WHEN f.annual_inc < 75000 THEN 2
        WHEN f.annual_inc < 120000 THEN 3
        ELSE 4
    END AS income_bracket_sort,

    -- 3. Credit Score Band
    CASE
        WHEN f.fico_range_low < 660 THEN 'Subprime (< 660)'
        WHEN f.fico_range_low < 700 THEN 'Near Prime (660 - 699)'
        WHEN f.fico_range_low < 740 THEN 'Prime (700 - 739)'
        ELSE 'Super Prime (740+)'
    END AS fico_band,

    -- 4. Credit Team Manual Review Flag (1 = Needs Manual Review)
    CASE
        WHEN f.dti >= 35
          OR f.fico_range_low < 660
          OR f.revol_util_over_100_flag = 1
          OR f.dti_999_flag = 1
          OR f.delinq_2yrs >= 2
        THEN 1
        ELSE 0
    END AS manual_review_flag
FROM fact_loan f;

-- Preview sample output
SELECT *
FROM vw_fact_loan_bi
LIMIT 15;