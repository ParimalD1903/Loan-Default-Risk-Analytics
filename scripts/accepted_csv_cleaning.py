import os
from pathlib import Path
import numpy as np
import pandas as pd


# ------------------------------------------------------------
# 1. PROJECT PATHS (OS-INDEPENDENT & REPO-RELATIVE)
# ------------------------------------------------------------

# Resolves to the repository root assuming this file lives in <repo_root>/scripts/
PROJECT_ROOT = Path(__file__).resolve().parent.parent

raw_path = Path(os.getenv("RAW_DATA_DIR", PROJECT_ROOT / "data" / "raw"))
cleaned_path = Path(os.getenv("CLEANED_DATA_DIR", PROJECT_ROOT / "data" / "cleaned"))

accepted_file = raw_path / "accepted_2007_to_2018Q4.csv"
cleaned_file = cleaned_path / "accepted_loans_cleaned.csv"
summary_file = cleaned_path / "excluded_summary_rows.csv"

cleaned_path.mkdir(parents=True, exist_ok=True)

if not accepted_file.exists():
    raise FileNotFoundError(
        f"Dataset not found at: {accepted_file}\n"
        "Download 'accepted_2007_to_2018Q4.csv' from the LendingClub Kaggle archive "
        "and place it inside 'data/raw/' (or test with 'data/sample_lending_club_100rows.csv')."
    )


# ------------------------------------------------------------
# 2. LOAD ONLY THE COLUMNS REQUIRED FOR THE PROJECT
# ------------------------------------------------------------

selected_columns = [
    "id",
    "loan_amnt",
    "term",
    "int_rate",
    "grade",
    "emp_length",
    "home_ownership",
    "annual_inc",
    "issue_d",
    "loan_status",
    "purpose",
    "addr_state",
    "dti",
    "delinq_2yrs",
    "fico_range_low",
    "revol_util"
]

df = pd.read_csv(
    accepted_file,
    usecols=selected_columns,
    dtype={"id": "string"},
    low_memory=False
)

print("Dataset loaded:", df.shape)


# ------------------------------------------------------------
# 3. REMOVE NON-LOAN SUMMARY/FOOTER ROWS
# ------------------------------------------------------------

id_numeric = pd.to_numeric(df["id"], errors="coerce")
summary_mask = id_numeric.isna()

summary_rows = df.loc[summary_mask].copy()
summary_rows.to_csv(summary_file, index=False)

df = df.loc[~summary_mask].copy()
df["id"] = pd.to_numeric(df["id"]).astype("int64")

print("Excluded non-numeric ID rows:", len(summary_rows))


# ------------------------------------------------------------
# 4. VALIDATE LOAN IDs
# ------------------------------------------------------------

duplicate_ids = df["id"].duplicated().sum()
print("Duplicate loan IDs:", duplicate_ids)

if duplicate_ids > 0:
    raise ValueError(
        "Duplicate loan IDs found. Investigate them before loading "
        "the data into MySQL; this script does not delete them."
    )


# ------------------------------------------------------------
# 5. STANDARDIZE CATEGORICAL COLUMNS
# ------------------------------------------------------------

categorical_columns = [
    "term",
    "grade",
    "emp_length",
    "home_ownership",
    "loan_status",
    "purpose",
    "addr_state"
]

for col in categorical_columns:
    df[col] = df[col].astype("string").str.strip()

df["grade"] = df["grade"].str.upper()
df["home_ownership"] = df["home_ownership"].str.upper()
df["addr_state"] = df["addr_state"].str.upper()
df["purpose"] = df["purpose"].str.lower()

# Treat blank categorical values as missing.
for col in categorical_columns:
    df[col] = df[col].replace("", pd.NA)

# Keep missing employment length as an explicit category.
df["emp_length"] = df["emp_length"].fillna("Unknown")


# ------------------------------------------------------------
# 6. STANDARDIZE LOAN STATUS AND PRESERVE CREDIT-POLICY FLAG
# ------------------------------------------------------------

df["credit_policy_flag"] = df["loan_status"].str.startswith(
    "Does not meet the credit policy",
    na=False
)

df["loan_status_clean"] = df["loan_status"].replace({
    "Does not meet the credit policy. Status:Fully Paid": "Fully Paid",
    "Does not meet the credit policy. Status:Charged Off": "Charged Off"
})


# ------------------------------------------------------------
# 7. TRANSFORM TERM AND ISSUE DATE
# ------------------------------------------------------------

df["term"] = pd.to_numeric(
    df["term"].str.replace("months", "", regex=False).str.strip(),
    errors="coerce"
)

df["issue_d"] = pd.to_datetime(
    df["issue_d"],
    format="%b-%Y",
    errors="coerce"
)


# ------------------------------------------------------------
# 8. CLEAN ANNUAL INCOME
# ------------------------------------------------------------

# Zero annual income was assessed and treated as missing.
df.loc[df["annual_inc"] == 0, "annual_inc"] = np.nan


# ------------------------------------------------------------
# 9. CLEAN DTI AND RETAIN A DATA-QUALITY FLAG
# ------------------------------------------------------------

# Negative DTI values are invalid for this analysis.
df.loc[df["dti"] < 0, "dti"] = np.nan

# Preserve a flag before replacing the special value 999 with missing.
df["dti_999_flag"] = df["dti"] == 999
df.loc[df["dti"] == 999, "dti"] = np.nan

# DTI values above 100 other than 999 are retained for now.
# They were inspected and should not be removed without a justified rule.


# ------------------------------------------------------------
# 10. RETAIN REVOLVING UTILIZATION VALUES AND ADD QUALITY FLAGS
# ------------------------------------------------------------

# Values above 100% can occur; retain the original values.
# Flags make unusually high values available for later analysis.
df["revol_util_over_100_flag"] = df["revol_util"] > 100
df["revol_util_over_200_flag"] = df["revol_util"] > 200


# ------------------------------------------------------------
# 11. CONVERT WHOLE-NUMBER COLUMNS TO APPROPRIATE TYPES
# ------------------------------------------------------------

# Loan amount is expected to contain whole-dollar values.
if df["loan_amnt"].isna().any():
    df["loan_amnt"] = df["loan_amnt"].astype("Int64")
else:
    df["loan_amnt"] = df["loan_amnt"].astype("int64")

# Nullable integer types preserve missing values if any exist.
df["fico_range_low"] = df["fico_range_low"].astype("Int64")
df["delinq_2yrs"] = df["delinq_2yrs"].astype("Int64")
df["term"] = df["term"].astype("Int64")


# ------------------------------------------------------------
# 12. FINAL VALIDATION
# ------------------------------------------------------------

print("\nFINAL DATASET CHECK")
print("-------------------")
print("Rows:", len(df))
print("Columns:", len(df.columns))
print("Duplicate loan IDs:", df["id"].duplicated().sum())
print("Duplicate complete rows:", df.duplicated().sum())

print("\nMissing values:")
print(df.isna().sum().sort_values(ascending=False))

print("\nData types:")
print(df.dtypes)

print("\nLoan status distribution:")
print(df["loan_status_clean"].value_counts(dropna=False))

print("\nLoan term distribution:")
print(df["term"].value_counts(dropna=False).sort_index())

print("\nIssue date range:")
print("Earliest:", df["issue_d"].min())
print("Latest:", df["issue_d"].max())

print("\nData-quality flags:")
print("DTI = 999:", df["dti_999_flag"].sum())
print("Revolving utilization > 100%:", df["revol_util_over_100_flag"].sum())
print("Revolving utilization > 200%:", df["revol_util_over_200_flag"].sum())
print("Credit-policy records:", df["credit_policy_flag"].sum())


# ------------------------------------------------------------
# 13. SAVE CLEANED DATA
# ------------------------------------------------------------

df.to_csv(cleaned_file, index=False)

print("\nCleaned dataset saved to:")
print(cleaned_file)
print("Final shape:", df.shape)