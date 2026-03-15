
  /*  MEDICAL INSURANCE FRAUD — COMPREHENSIVE SQL SERVER ANALYSIS         
       Database : Insurance                                                 
       Tables   : Fraud_Analysis  |  Provider_Registry                     
       Dataset  : 22,000 Claims · 500 Providers · Jan 2021 – Dec 2024      
       Role     : Data Analyst Performance Lead                    */    
        
   
        
 /*  TABLE OF CONTENTS    
 
  SECTION 01 │ Data Quality Audit & Profiling                                 
  SECTION 02 │ Executive KPI Dashboard                                        
  SECTION 03 │ Fraud Pattern Deep-Dive                                        
  SECTION 04 │ Provider Risk Intelligence                                     
  SECTION 05 │ Geographic & State-Level Heat Map                              
  SECTION 06 │ Temporal Trend Analysis (YoY / QoQ / Monthly)                 
  SECTION 07 │ Financial Exposure & Revenue Leakage                         
  SECTION 08 │ Behavioral Anomaly Detection                                  
  SECTION 09 │ Insurer & Payer Performance                                   
  SECTION 10 │ Patient Demography & Vulnerability                             
  SECTION 11 │ Specialty Risk Stratification                                  
  SECTION 12 │ Multi-Flag Composite Risk Scoring                              
  SECTION 13 │ Master Investigative Priority Queue   */
  
                       

-- Retrieve all transactional data from the Fraud_Analysis table for auditing and pattern detection.
Select * 
From dbo.Fraud_Analysis;

-- Fetch the complete list of registered healthcare providers to verify credentials and status.
Select *
From dbo.Provider_Registry;

/* SECTION 01 │ DATA QUALITY AUDIT & PROFILING */

-- 01.A │ Row counts
SELECT 'Fraud_Analysis'AS [Table], COUNT(*) AS Rows FROM dbo.Fraud_Analysis
UNION ALL
SELECT 'Provider_Registry',COUNT(*) FROM dbo.Provider_Registry;

-- 01.B │ NULL / missing values audit — Fraud_Analysis
SELECT
    SUM(CASE WHEN Claim_ID IS NULL THEN 1 ELSE 0 END) AS Null_ClaimID,
    SUM(CASE WHEN Provider_ID IS NULL THEN 1 ELSE 0 END) AS Null_ProviderID,
    SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) AS Null_PatientID,
    SUM(CASE WHEN Fraud_Type IS NULL THEN 1 ELSE 0 END) AS Null_FraudType,
    SUM(CASE WHEN Billed_Amount IS NULL THEN 1 ELSE 0 END) AS Null_BilledAmt,
    SUM(CASE WHEN Paid_Amount IS NULL THEN 1 ELSE 0 END) AS Null_PaidAmt,
    SUM(CASE WHEN Claim_Date IS NULL THEN 1 ELSE 0 END) AS Null_ClaimDate,
    COUNT(*) AS Total_Rows
FROM dbo.Fraud_Analysis;

-- 01.C │ NULL audit — Provider_Registry
SELECT
    SUM(CASE WHEN Provider_ID IS NULL THEN 1 ELSE 0 END) AS Null_ProviderID,
    SUM(CASE WHEN Specialty IS NULL THEN 1 ELSE 0 END) AS Null_Specialty,
    SUM(CASE WHEN State IS NULL THEN 1 ELSE 0 END) AS Null_State,
    COUNT(*) AS Total_Rows
FROM dbo.Provider_Registry;

-- 01.D │ Duplicate Claim_ID check
SELECT Claim_ID, COUNT(*) AS Occurrences
FROM dbo.Fraud_Analysis
GROUP BY Claim_ID
HAVING COUNT(*) > 1;

-- 01.E │ Orphan Provider_IDs (claims with no registry record)
SELECT DISTINCT fa.Provider_ID
FROM dbo.Fraud_Analysis  fa
LEFT JOIN dbo.Provider_Registry pr ON fa.Provider_ID = pr.Provider_ID
WHERE pr.Provider_ID IS NULL;

-- 01.F │ Financial integrity — paid > billed anomaly
SELECT
    COUNT(*) AS Overpayment_Count,
    SUM(Paid_Amount - Billed_Amount) AS Total_Excess_Paid
FROM dbo.Fraud_Analysis
WHERE Paid_Amount > Billed_Amount;

-- 01.G │ Unit mismatch cross-check (raw vs flag)
SELECT
    SUM(CASE WHEN Units_Billed <> Units_Rendered THEN 1 ELSE 0 END) AS Raw_Mismatch,
    SUM(CAST(Flag_UnitMismatch AS INT)) AS Flagged_Mismatch,
    SUM(CASE WHEN Units_Billed <> Units_Rendered
             AND Flag_UnitMismatch = 0 THEN 1 ELSE 0 END) AS Missed_By_Flag
FROM dbo.Fraud_Analysis;

-- 01.H │ Date range and year distribution
SELECT
    MIN(Claim_Date) AS Earliest,
    MAX(Claim_Date) AS Latest,
    DATEDIFF(DAY, MIN(Claim_Date), MAX(Claim_Date)) AS Span_Days
FROM dbo.Fraud_Analysis;

SELECT
    Claim_Year,
    COUNT(*) AS Claims,
    CAST(COUNT(*) * 100.0 / 22000 AS DECIMAL(5,2)) AS Pct
FROM dbo.Fraud_Analysis
GROUP BY Claim_Year
ORDER BY Claim_Year;

-- 01.I │ Fraud_Type NULL context — confirm NULLs = legitimate claims only
SELECT
    Fraud_Label,
    COUNT(*) AS Claims,
    SUM(CASE WHEN Fraud_Type IS NULL THEN 1 ELSE 0 END) AS Null_FraudType,
    SUM(CASE WHEN Fraud_Type IS NOT NULL THEN 1 ELSE 0 END) AS Has_FraudType
FROM dbo.Fraud_Analysis
GROUP BY Fraud_Label;


/* SECTION 02 │ EXECUTIVE KPI DASHBOARD */

-- 02.A │ Single-row KPI summary
SELECT
    -- Volume
    COUNT(*) AS Total_Claims,
    COUNT(DISTINCT fa.Provider_ID) AS Unique_Providers,
    COUNT(DISTINCT fa.Patient_ID) AS Unique_Patients,
    COUNT(DISTINCT fa.Provider_State) AS States_Covered,

    -- Financials
    CAST(SUM(fa.Billed_Amount)  / 1e6 AS DECIMAL(10,3)) AS Total_Billed_M,
    CAST(SUM(fa.Allowed_Amount) / 1e6 AS DECIMAL(10,3)) AS Total_Allowed_M,
    CAST(SUM(fa.Paid_Amount) / 1e6 AS DECIMAL(10,3)) AS Total_Paid_M,
    CAST((SUM(fa.Billed_Amount) - SUM(fa.Paid_Amount)) / 1e6 AS DECIMAL(10,3)) AS Billed_vs_Paid_Gap_M,

    -- Fraud KPIs
    SUM(CAST(fa.Fraud_Label AS INT)) AS Confirmed_Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Overall_Fraud_Rate_Pct,
    CAST(SUM(CASE WHEN fa.Fraud_Label = 1 THEN fa.Billed_Amount ELSE 0 END) / 1e6 AS DECIMAL(10,3)) AS Fraud_Billed_M,
    CAST(SUM(CASE WHEN fa.Fraud_Label = 1 THEN fa.Paid_Amount ELSE 0 END) / 1e6
    AS DECIMAL(10,3)) AS Fraud_Paid_M,

    -- Risk
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,2)) AS Avg_Risk_Score,
    SUM(CASE WHEN fa.Fraud_Risk_Score >= 70 THEN 1 ELSE 0 END) AS Critical_Risk_Claims,
                                                          
    -- Flag Totals
    SUM(CAST(fa.Flag_HighValue AS INT)) AS Flag_HighValue,
    SUM(CAST(fa.Flag_Weekend AS INT)) AS Flag_Weekend,
    SUM(CAST(fa.Flag_SameDay_Volume AS INT)) AS Flag_SameDay,
    SUM(CAST(fa.Flag_UnitMismatch AS INT)) AS Flag_UnitMismatch,
    SUM(CAST(fa.Flag_Duplicate AS INT)) AS Flag_Duplicate,

    -- Provider risk (from registry)
    SUM(CAST(pr.Is_Fraudulent AS INT)) AS Known_Fraudulent_Providers,
    SUM(CASE WHEN pr.Is_Fraudulent = 1
             AND pr.License_Valid  = 1 THEN 1 ELSE 0 END) AS Fraudulent_Still_Licensed
FROM dbo.Fraud_Analysis fa
JOIN dbo.Provider_Registry pr ON fa.Provider_ID = pr.Provider_ID;

-- 02.B │ Claim status breakdown
SELECT
    fa.Claim_Status,
    COUNT(*) AS Claims,
    CAST(COUNT(*) * 100.0 / 22000 AS DECIMAL(5,2))  AS Pct_Total,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(fa.Billed_Amount)/ 1e3 AS DECIMAL(12,1)) AS Billed_K,
    CAST(SUM(fa.Paid_Amount)/ 1e3 AS DECIMAL(12,1)) AS Paid_K,
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Claim_Status
ORDER BY Claims DESC;

-- 02.C │ Network status split (In vs Out-of-Network)
SELECT
    fa.Network_Status,
    COUNT(*) AS Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(fa.Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(AVG(fa.Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed,
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Network_Status;


/* SECTION 03 │ FRAUD PATTERN DEEP-DIVE */

-- 03.A │ Fraud type volume, financial exposure, risk score
SELECT
    ISNULL(fa.Fraud_Type, 'No Fraud — Legitimate') AS Fraud_Type,
    COUNT(*) AS Claims,
    CAST(COUNT(*) * 100.0 / 22000 AS DECIMAL(5,2))  AS Pct_Total,
    COUNT(DISTINCT fa.Provider_ID) AS Providers_Involved,
    COUNT(DISTINCT fa.Patient_ID) AS Patients_Affected,
    CAST(SUM(fa.Billed_Amount) AS DECIMAL(14,2)) AS Total_Billed,
    CAST(SUM(fa.Paid_Amount) AS DECIMAL(14,2)) AS Total_Paid,
    CAST(AVG(fa.Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed,
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Fraud_Type
ORDER BY Claims DESC;

-- 03.B │ Fraud type × Specialty cross-tab (pivot-ready)
SELECT
    fa.Specialty,
    COUNT(*) AS Total_Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Total_Fraud,
    SUM(CASE WHEN fa.Fraud_Type = 'Upcoding' THEN 1 ELSE 0 END) AS Upcoding,
    SUM(CASE WHEN fa.Fraud_Type = 'Unbundling' THEN 1 ELSE 0 END) AS Unbundling,
    SUM(CASE WHEN fa.Fraud_Type = 'Phantom Billing'THEN 1 ELSE 0 END) AS Phantom_Billing,
    SUM(CASE WHEN fa.Fraud_Type = 'Duplicate Claim' THEN 1 ELSE 0 END) AS Duplicate_Claim,
    SUM(CASE WHEN fa.Fraud_Type = 'Medical Identity Theft' THEN 1 ELSE 0 END) AS Identity_Theft,
    SUM(CASE WHEN fa.Fraud_Type = 'Kickback - Referral' THEN 1 ELSE 0 END) AS Kickback_Referral
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Specialty
ORDER BY Total_Fraud DESC;

-- 03.C │ Fraud by Insurer
SELECT
    fa.Insurer,
    COUNT(*) AS Total_Claims,
    SUM(CAST(fa.Fraud_Label AS INT))AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(CASE WHEN fa.Fraud_Label = 1 THEN fa.Paid_Amount ELSE 0 END) / 1e3
         AS DECIMAL(12,1))AS Fraud_Paid_K,
    CAST(AVG(CASE WHEN fa.Fraud_Label = 1
                  THEN CAST(fa.Fraud_Risk_Score AS FLOAT) END)
         AS DECIMAL(5,1))AS Avg_Fraud_Risk
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Insurer
ORDER BY Fraud_Paid_K DESC;

-- 03.D │ Weekend fraud concentration
SELECT
    fa.Flag_Weekend,
    CASE fa.Flag_Weekend WHEN 1 THEN 'Weekend' ELSE 'Weekday' END AS Day_Type,
    COUNT(*) AS Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(AVG(fa.Billed_Amount)  AS DECIMAL(10,2)) AS Avg_Billed,
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Flag_Weekend;

-- 03.E │ All-5-flag claims — highest possible alert level
SELECT
    fa.Claim_ID, fa.Provider_ID, fa.Provider_Name, fa.Specialty,
    fa.Patient_ID, fa.Claim_Date, fa.Fraud_Type,
    CAST(fa.Billed_Amount AS DECIMAL(12,2)) AS Billed,
    CAST(fa.Paid_Amount AS DECIMAL(12,2)) AS Paid,
    fa.Fraud_Risk_Score,
    fa.Claim_Status,
    pr.Is_Fraudulent,
    pr.License_Valid
FROM dbo.Fraud_Analysis    fa
JOIN dbo.Provider_Registry pr ON fa.Provider_ID = pr.Provider_ID
WHERE fa.Flag_HighValue  = 1
  AND fa.Flag_Weekend  = 1
  AND fa.Flag_SameDay_Volume = 1
  AND fa.Flag_UnitMismatch  = 1
  AND fa.Flag_Duplicate = 1
ORDER BY fa.Fraud_Risk_Score DESC, fa.Billed_Amount DESC;

-- 03.F │ Fraud rate by number of active flags
SELECT
    (CAST(fa.Flag_HighValue AS INT)
     + CAST(fa.Flag_Weekend AS INT)
     + CAST(fa.Flag_SameDay_Volume AS INT)
     + CAST(fa.Flag_UnitMismatch AS INT)
     + CAST(fa.Flag_Duplicate AS INT))  AS Active_Flags,
    COUNT(*) AS Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score,
    CAST(AVG(fa.Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed
FROM dbo.Fraud_Analysis fa
GROUP BY (CAST(fa.Flag_HighValue AS INT)
     + CAST(fa.Flag_Weekend AS INT)
     + CAST(fa.Flag_SameDay_Volume AS INT)
     + CAST(fa.Flag_UnitMismatch AS INT)
     + CAST(fa.Flag_Duplicate AS INT))
ORDER BY Active_Flags;


/* SECTION 04 │ PROVIDER RISK INTELLIGENCE */

-- 04.A │ Full provider scorecard (joins both tables)
WITH ProviderStats AS (
    SELECT
        fa.Provider_ID,
        fa.Provider_Name,
        fa.Specialty,
        fa.Provider_State,
        COUNT(*) AS Total_Claims,
        COUNT(DISTINCT fa.Patient_ID) AS Unique_Patients,
        SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
        CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
        CAST(SUM(fa.Billed_Amount) / 1e3 AS DECIMAL(12,1)) AS Total_Billed_K,
        CAST(SUM(fa.Paid_Amount) / 1e3 AS DECIMAL(12,1)) AS Total_Paid_K,
        CAST(AVG(fa.Billed_Amount) AS DECIMAL(10,2)) AS Avg_Claim_Value,
        CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1))AS Avg_Risk_Score,
        SUM(CAST(fa.Flag_HighValue AS INT)) AS HighValue_Flags,
        SUM(CAST(fa.Flag_Weekend AS INT)) AS Weekend_Claims,
        SUM(CAST(fa.Flag_UnitMismatch AS INT)) AS Unit_Mismatches,
        SUM(CAST(fa.Flag_Duplicate AS INT)) AS Duplicate_Flags,
        SUM(CAST(fa.Flag_SameDay_Volume AS INT)) AS SameDay_Flags,
        CAST(COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT fa.Patient_ID), 0) AS DECIMAL(6,2)) AS Claims_Per_Patient,
        SUM(CASE WHEN fa.Claim_Status = 'Denied' THEN 1 ELSE 0 END)  * 1.0 / NULLIF(COUNT(*), 0) AS Denial_Rate
    FROM dbo.Fraud_Analysis fa
    GROUP BY fa.Provider_ID, fa.Provider_Name, fa.Specialty, fa.Provider_State
)
SELECT
    ps.*,
    pr.Is_Fraudulent,
    pr.License_Valid,
    pr.Years_Practice,
    pr.Network_Status,
    CASE
        WHEN ps.Fraud_Rate_Pct >= 80 THEN 'CRITICAL'
        WHEN ps.Fraud_Rate_Pct >= 50 THEN 'HIGH'
        WHEN ps.Fraud_Rate_Pct >= 25 THEN 'MODERATE'
        WHEN ps.Fraud_Rate_Pct >= 10 THEN 'LOW'
        ELSE 'CLEAN'
    END AS Risk_Band,
    RANK() OVER (ORDER BY ps.Fraud_Rate_Pct DESC,
                          ps.Avg_Risk_Score  DESC) AS Risk_Rank
FROM ProviderStats ps
JOIN dbo.Provider_Registry pr ON ps.Provider_ID = pr.Provider_ID
ORDER BY Risk_Rank;

-- 04.B │ Top 20 riskiest providers — investigation hit list
WITH ProviderScore AS (
    SELECT
        fa.Provider_ID,
        fa.Provider_Name,
        fa.Specialty,
        fa.Provider_State,
        COUNT(*) AS Total_Claims,
        SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
        CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
        CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score,
        CAST(SUM(fa.Billed_Amount) / 1e3 AS DECIMAL(12,1)) AS Billed_K,
        SUM(CAST(fa.Flag_UnitMismatch AS INT)) AS Unit_Mismatches,
        SUM(CAST(fa.Flag_Duplicate AS INT)) AS Dup_Flags,
        SUM(CAST(fa.Flag_Weekend AS INT)) AS Weekend_Claims
    FROM dbo.Fraud_Analysis fa
    GROUP BY fa.Provider_ID, fa.Provider_Name, fa.Specialty, fa.Provider_State
)
SELECT TOP 20
    ROW_NUMBER() OVER (ORDER BY ps.Fraud_Rate_Pct DESC, ps.Avg_Risk_Score DESC) AS Rank,
    ps.Provider_ID,
    ps.Provider_Name,
    ps.Specialty,
    ps.Provider_State,
    ps.Total_Claims,
    ps.Fraud_Claims,
    ps.Fraud_Rate_Pct,
    ps.Avg_Risk_Score,
    ps.Billed_K,
    ps.Unit_Mismatches,
    ps.Dup_Flags,
    ps.Weekend_Claims,
    pr.Is_Fraudulent,
    pr.License_Valid,
    pr.Years_Practice,
    CASE
        WHEN pr.Is_Fraudulent = 1 AND pr.License_Valid = 1
             THEN ' REVOKE LICENSE + AUDIT'
        WHEN ps.Fraud_Rate_Pct >= 80
             THEN ' IMMEDIATE INVESTIGATION'
        ELSE ' PRIORITY AUDIT'
    END AS Recommended_Action
FROM ProviderScore ps
JOIN dbo.Provider_Registry pr ON ps.Provider_ID = pr.Provider_ID
ORDER BY ps.Fraud_Rate_Pct DESC, ps.Avg_Risk_Score DESC;

-- 04.C │ Compliance gap — known fraudulent providers still holding valid license
SELECT
    pr.Provider_ID,
    pr.Provider_Name,
    pr.Specialty,
    pr.State,
    pr.Years_Practice,
    pr.Network_Status,
    COUNT(fa.Claim_ID) AS Total_Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(fa.Billed_Amount) / 1e3 AS DECIMAL(12,1)) AS Billed_K
FROM dbo.Provider_Registry pr
JOIN dbo.Fraud_Analysis    fa ON pr.Provider_ID = fa.Provider_ID
WHERE pr.Is_Fraudulent = 1
  AND pr.License_Valid = 1
GROUP BY pr.Provider_ID, pr.Provider_Name, pr.Specialty,
          pr.State, pr.Years_Practice, pr.Network_Status
ORDER BY Fraud_Claims DESC;

-- 04.D │ Out-of-network providers with elevated fraud
SELECT
    pr.Provider_ID,
    pr.Provider_Name,
    pr.Specialty,
    pr.State,
    COUNT(fa.Claim_ID) AS Total_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(fa.Billed_Amount) / 1e3 AS DECIMAL(12,1)) AS Billed_K,
    pr.Is_Fraudulent,
    pr.License_Valid
FROM dbo.Provider_Registry pr
JOIN dbo.Fraud_Analysis fa ON pr.Provider_ID = fa.Provider_ID
WHERE pr.Network_Status = 'Out-of-Network'
GROUP  BY pr.Provider_ID, pr.Provider_Name, pr.Specialty,
          pr.State, pr.Is_Fraudulent, pr.License_Valid
HAVING AVG(CAST(fa.Fraud_Label AS FLOAT)) > 0.30
ORDER  BY Fraud_Rate_Pct DESC;

-- 04.E │ Provider YoY fraud trend (accelerating providers)
WITH ProviderYearly AS (
    SELECT
        Provider_ID, Provider_Name, Specialty,
        Claim_Year,
        COUNT(*) AS Claims,
        SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
        CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct
    FROM dbo.Fraud_Analysis
    WHERE Claim_Year >= 2021
    GROUP BY Provider_ID, Provider_Name, Specialty, Claim_Year
)
SELECT
    Provider_ID, Provider_Name, Specialty,
    Claim_Year, Claims, Fraud_Rate_Pct,
    LAG(Fraud_Rate_Pct) OVER (PARTITION BY Provider_ID ORDER BY Claim_Year) AS Prev_Year_Rate,
    CAST(Fraud_Rate_Pct - ISNULL(LAG(Fraud_Rate_Pct) OVER (PARTITION BY Provider_ID ORDER BY Claim_Year),
           Fraud_Rate_Pct) AS DECIMAL(5,2)) AS YoY_Change_PP
FROM ProviderYearly
WHERE Fraud_Rate_Pct > 0
ORDER BY YoY_Change_PP DESC
OFFSET 0 ROWS FETCH NEXT 30 ROWS ONLY;

-- 04.F │ Claims-per-patient ratio — patient churning / unbundling signal
SELECT
    Provider_ID, Provider_Name, Specialty, Provider_State,
    COUNT(DISTINCT Patient_ID) AS Unique_Patients,
    COUNT(*) AS Total_Claims,
    CAST(COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT Patient_ID), 0) AS DECIMAL(6,2)) AS Claims_Per_Patient,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct
FROM dbo.Fraud_Analysis
GROUP BY Provider_ID, Provider_Name, Specialty, Provider_State
ORDER BY Claims_Per_Patient DESC
OFFSET 0 ROWS FETCH NEXT 30 ROWS ONLY;


/* SECTION 05 │ GEOGRAPHIC & STATE-LEVEL HEAT MAP */

-- 05.A │ Full state fraud leaderboard
SELECT
    Provider_State AS State,
    COUNT(*) AS Total_Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(SUM(Paid_Amount) / 1e6 AS DECIMAL(10,3)) AS Paid_M,
    CAST(AVG(CAST(Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score,
    RANK() OVER (ORDER BY AVG(CAST(Fraud_Label AS FLOAT)) DESC) AS Fraud_Rate_Rank,
    RANK() OVER (ORDER BY SUM(CAST(Fraud_Label AS INT)) DESC) AS Volume_Rank
FROM dbo.Fraud_Analysis
GROUP BY Provider_State
ORDER BY Fraud_Rate_Pct DESC;

-- 05.B │ States above national fraud average
WITH NatAvg AS (
    SELECT AVG(CAST(Fraud_Label AS FLOAT)) AS National_Rate
    FROM dbo.Fraud_Analysis
),
StateRates AS (
    SELECT
        Provider_State,
        AVG(CAST(Fraud_Label AS FLOAT)) AS State_Rate,
        COUNT(*) AS Claims,
        SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims
    FROM dbo.Fraud_Analysis
    GROUP BY Provider_State
)
SELECT
    sr.Provider_State,
    CAST(sr.State_Rate * 100 AS DECIMAL(5,2)) AS State_Fraud_Pct,
    CAST(na.National_Rate * 100 AS DECIMAL(5,2)) AS National_Avg_Pct,
    CAST((sr.State_Rate - na.National_Rate) * 100 AS DECIMAL(5,2)) AS Above_National_PP,
    sr.Claims,
    sr.Fraud_Claims
FROM StateRates sr
CROSS JOIN NatAvg na
WHERE sr.State_Rate > na.National_Rate
ORDER BY Above_National_PP DESC;

-- 05.C │ Cross-state billing — provider state ≠ patient state
SELECT
    fa.Provider_State,
    fa.Patient_State,
    COUNT(*) AS Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(fa.Billed_Amount) / 1e3 AS DECIMAL(12,1)) AS Billed_K
FROM dbo.Fraud_Analysis fa
WHERE fa.Provider_State <> fa.Patient_State
GROUP BY fa.Provider_State, fa.Patient_State
HAVING COUNT(*) > 30
ORDER BY Fraud_Rate_Pct DESC;

-- 05.D │ High-volume states with disproportionate fraud
SELECT
    Provider_State,
    COUNT(*) AS Total_Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(Billed_Amount) / 1e6 AS DECIMAL(10,3))AS Billed_M
FROM dbo.Fraud_Analysis
GROUP BY Provider_State
HAVING COUNT(*) > 400 AND AVG(CAST(Fraud_Label AS FLOAT)) > 0.35
ORDER BY Fraud_Rate_Pct DESC;


/*  SECTION 06 │ TEMPORAL TREND ANALYSIS  (YoY / QoQ / Monthly) */

-- 06.A │ Year-over-Year fraud trend
WITH YearStats AS (
    SELECT
        Claim_Year,
        COUNT(*) AS Claims,
        SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
        CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
        CAST(SUM(Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
        CAST(SUM(CASE WHEN Fraud_Label = 1 THEN Paid_Amount ELSE 0 END) / 1e6  AS DECIMAL(10,3)) AS Fraud_Paid_M,
        CAST(AVG(Billed_Amount) AS DECIMAL(10,2)) AS Avg_Claim_Value
    FROM dbo.Fraud_Analysis
    WHERE Claim_Year >= 2021
    GROUP BY Claim_Year
)
SELECT
    Claim_Year,
    Claims,
    Fraud_Claims,
    Fraud_Rate_Pct,
    Billed_M,
    Fraud_Paid_M,
    Avg_Claim_Value,
    LAG(Fraud_Rate_Pct) OVER (ORDER BY Claim_Year) AS Prev_Fraud_Rate_Pct,
    CAST(Fraud_Rate_Pct - ISNULL(LAG(Fraud_Rate_Pct) OVER (ORDER BY Claim_Year), Fraud_Rate_Pct) AS DECIMAL(5,2)) AS YoY_Fraud_Change_PP,
    CAST((Fraud_Paid_M - ISNULL(LAG(Fraud_Paid_M) OVER (ORDER BY Claim_Year), Fraud_Paid_M)) / NULLIF(LAG(Fraud_Paid_M) OVER (ORDER BY Claim_Year), 0) * 100
         AS DECIMAL(5,1)) AS Fraud_Paid_Growth_Pct
FROM YearStats
ORDER BY Claim_Year;

-- 06.B │ Quarterly trend — seasonality check
SELECT
    Claim_Year,
    Claim_Quarter,
    COUNT(*) AS Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(AVG(CAST(Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk
FROM dbo.Fraud_Analysis
WHERE Claim_Year >= 2021
GROUP BY Claim_Year, Claim_Quarter
ORDER BY Claim_Year, Claim_Quarter;

-- 06.C │ Monthly seasonality pattern (all years combined)
SELECT
    Claim_Month,
    COUNT(*) AS Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(AVG(Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed,
    SUM(CAST(Flag_HighValue AS INT)) AS HighValue_Flags
FROM dbo.Fraud_Analysis
GROUP BY Claim_Month
ORDER BY
    CASE Claim_Month
        WHEN 'Jan' THEN 1  WHEN 'Feb' THEN 2  WHEN 'Mar' THEN 3
        WHEN 'Apr' THEN 4  WHEN 'May' THEN 5  WHEN 'Jun' THEN 6
        WHEN 'Jul' THEN 7  WHEN 'Aug' THEN 8  WHEN 'Sep' THEN 9
        WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12
    END;

-- 06.D │ Rolling 4-quarter fraud rate (window function)
WITH Quarters AS (
    SELECT
        Claim_Year,
        Claim_Quarter,
        COUNT(*) AS Claims,
        CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate
    FROM dbo.Fraud_Analysis
    WHERE Claim_Year >= 2021
    GROUP BY Claim_Year, Claim_Quarter
)
SELECT
    Claim_Year,
    Claim_Quarter,
    Claims,
    Fraud_Rate,
    CAST(AVG(Fraud_Rate) OVER (
        ORDER BY Claim_Year, Claim_Quarter
        ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ) AS DECIMAL(5,2)) AS Rolling_4Q_Avg
FROM Quarters
ORDER BY Claim_Year, Claim_Quarter;

-- 06.E │ Claim velocity spike — providers whose volume grew > 100% YoY
WITH Yearly AS (
    SELECT Provider_ID, Claim_Year, COUNT(*) AS Claims
    FROM dbo.Fraud_Analysis
    WHERE Claim_Year IN (2022, 2023, 2024)
    GROUP BY Provider_ID, Claim_Year
)
SELECT TOP 20
    y2.Provider_ID,
    fa.Provider_Name,
    fa.Specialty,
    y1.Claims AS Prior_Year_Claims,
    y2.Claims AS Current_Year_Claims,
    CAST((y2.Claims - y1.Claims) * 100.0 / NULLIF(y1.Claims, 0) AS DECIMAL(6,1)) AS Volume_Growth_Pct,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Overall_Fraud_Rate_Pct
FROM Yearly y1
JOIN Yearly y2
    ON  y1.Provider_ID = y2.Provider_ID
    AND y2.Claim_Year  = y1.Claim_Year + 1
JOIN dbo.Fraud_Analysis fa ON y2.Provider_ID = fa.Provider_ID
WHERE (y2.Claims - y1.Claims) * 100.0 / NULLIF(y1.Claims, 0) > 100
GROUP BY y2.Provider_ID, fa.Provider_Name, fa.Specialty,
          y1.Claims, y2.Claims
ORDER BY Volume_Growth_Pct DESC;


/* SECTION 07 │ FINANCIAL EXPOSURE & REVENUE LEAKAGE */

-- 07.A │ Total financial exposure — fraud vs legitimate
SELECT
    CASE fa.Fraud_Label WHEN 1 THEN 'Fraudulent' ELSE 'Legitimate' END AS Category,
    COUNT(*) AS Claims,
    CAST(SUM(fa.Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(SUM(fa.Allowed_Amount) / 1e6 AS DECIMAL(10,3)) AS Allowed_M,
    CAST(SUM(fa.Paid_Amount) / 1e6 AS DECIMAL(10,3)) AS Paid_M,
    CAST((SUM(fa.Billed_Amount) - SUM(fa.Paid_Amount)) / 1e6 AS DECIMAL(10,3)) AS Denied_Gap_M,
    CAST(SUM(fa.Paid_Amount) / NULLIF(SUM(fa.Billed_Amount), 0) * 100 AS DECIMAL(5,1)) AS Pay_Rate_Pct
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Fraud_Label;

-- 07.B │ Specialty billing efficiency (billed vs paid gap)
SELECT
    fa.Specialty,
    COUNT(*) AS Claims,
    CAST(SUM(fa.Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(SUM(fa.Paid_Amount) / 1e6 AS DECIMAL(10,3))  AS Paid_M,
    CAST((SUM(fa.Billed_Amount) - SUM(fa.Paid_Amount)) / 1e6 AS DECIMAL(10,3)) AS Gap_M,
    CAST((SUM(fa.Billed_Amount) - SUM(fa.Paid_Amount)) / NULLIF(SUM(fa.Billed_Amount), 0) * 100 AS DECIMAL(5,1)) AS Gap_Pct,
    CAST(AVG(fa.Billed_Amount / NULLIF(fa.Allowed_Amount, 0)) AS DECIMAL(5,2)) AS Bill_to_Allow_Ratio
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Specialty
ORDER BY Gap_M DESC;

-- 07.C │ Top 50 highest-value fraud claims
SELECT TOP 50
    fa.Claim_ID,
    fa.Claim_Date,
    fa.Provider_Name,
    fa.Specialty,
    fa.Provider_State,
    fa.Patient_ID,
    fa.Insurer,
    fa.CPT_Description,
    fa.Fraud_Type,
    fa.Units_Billed,
    fa.Units_Rendered,
    CAST(fa.Billed_Amount AS DECIMAL(12,2)) AS Billed,
    CAST(fa.Paid_Amount AS DECIMAL(12,2)) AS Paid,
    fa.Fraud_Risk_Score,
    fa.Claim_Status,
    pr.Is_Fraudulent,
    pr.License_Valid
FROM dbo.Fraud_Analysis fa
JOIN dbo.Provider_Registry pr ON fa.Provider_ID = pr.Provider_ID
WHERE fa.Fraud_Label = 1
  AND fa.Billed_Amount > 5000
ORDER BY fa.Billed_Amount DESC;

-- 07.D │ Unit mismatch overbilling — estimated overcharge per provider
SELECT
    Provider_ID,
    Provider_Name,
    Specialty,
    COUNT(*) AS Mismatch_Claims,
    SUM(Units_Billed - Units_Rendered) AS Total_Extra_Units,
    CAST(AVG(CAST(Units_Billed - Units_Rendered AS FLOAT)) AS DECIMAL(5,2)) AS Avg_Extra_Units,
    CAST(SUM((Units_Billed - Units_Rendered) * (Billed_Amount / NULLIF(Units_Billed, 0))) AS DECIMAL(14,2)) AS Est_Overbilled
FROM dbo.Fraud_Analysis
WHERE Units_Billed > Units_Rendered
GROUP BY Provider_ID, Provider_Name, Specialty
ORDER BY Est_Overbilled DESC;

-- 07.E │ Insurer pay-rate analysis — which payers are being overexploited?
SELECT
    Insurer,
    COUNT(*)  AS Claims,
    CAST(SUM(Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(SUM(Paid_Amount) / 1e6 AS DECIMAL(10,3)) AS Paid_M,
    CAST(SUM(Paid_Amount) / NULLIF(SUM(Billed_Amount), 0) * 100  AS DECIMAL(5,1)) AS Pay_Rate_Pct,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(SUM(CASE WHEN Fraud_Label = 1 THEN Paid_Amount ELSE 0 END) / 1e AS DECIMAL(10,3)) AS Fraud_Leakage_M
FROM dbo.Fraud_Analysis
GROUP BY Insurer
ORDER BY Fraud_Leakage_M DESC;


/* SECTION 08 │ BEHAVIORAL ANOMALY DETECTION */

-- 08.A │ Same-day billing surge — impossible clinical workload
WITH DailyLoad AS (
    SELECT
        Provider_ID,
        Provider_Name,
        Specialty,
        Claim_Date,
        COUNT(*) AS Claims_That_Day,
        COUNT(DISTINCT Patient_ID) AS Patients_That_Day,
        CAST(SUM(Billed_Amount) AS DECIMAL(12,2))AS Daily_Billed,
        SUM(CAST(Fraud_Label AS INT)) AS Fraud_That_Day
    FROM dbo.Fraud_Analysis
    GROUP BY Provider_ID, Provider_Name, Specialty, Claim_Date
)
SELECT TOP 30
    Provider_ID, Provider_Name, Specialty, Claim_Date,
    Claims_That_Day,
    Patients_That_Day,
    Daily_Billed,
    Fraud_That_Day,
    CAST(Claims_That_Day * 1.0 / NULLIF(Patients_That_Day, 0) AS DECIMAL(5,2)) AS Claims_Per_Patient
FROM DailyLoad
WHERE Claims_That_Day >= 10
ORDER BY Claims_That_Day DESC;

-- 08.b │ Patient fraud ring — visiting excessive number of providers
WITH PatientMulti AS (
    SELECT 
        Patient_ID,
        Patient_Age,
        Patient_Gender,
        Patient_State,
        COUNT(*) AS Total_Claims,
        COUNT(DISTINCT Provider_ID) AS Unique_Providers,
        COUNT(DISTINCT Insurer) AS Insurers_Used,
        SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
        CAST(SUM(Billed_Amount) / 1e3 AS DECIMAL(10,1)) AS Total_Billed_K,
        STRING_AGG(CAST(Fraud_Type AS VARCHAR(MAX)), ' | ') WITHIN GROUP (ORDER BY Fraud_Type) AS Fraud_Types
    FROM dbo.Fraud_Analysis
    GROUP BY Patient_ID, Patient_Age, Patient_Gender, Patient_State
)
SELECT TOP 30
    Patient_ID, 
    Patient_Age, 
    Patient_Gender, 
    Patient_State,
    Total_Claims, 
    Unique_Providers, 
    Insurers_Used,
    Fraud_Claims,
    CAST(Fraud_Claims * 100.0 / NULLIF(Total_Claims, 0) AS DECIMAL(5,1)) AS Fraud_Rate_Pct,
    Total_Billed_K,
    Fraud_Types
FROM PatientMulti
WHERE Unique_Providers >= 5
ORDER BY Unique_Providers DESC, Total_Billed_K DESC;

-- 08.c │ CPT upcoding outliers — claims billed > 2 std dev above specialty mean
WITH CPT_Stats AS (
    SELECT
        CPT_Code,
        CPT_Description,
        Specialty,
        COUNT(*) AS Usage_Count,
        AVG(Billed_Amount) AS Avg_Billed,
        STDEV(Billed_Amount) AS StDev_Billed,
        AVG(Billed_Amount) + 2 * STDEV(Billed_Amount) AS UCL  
    FROM dbo.Fraud_Analysis
    GROUP BY CPT_Code, CPT_Description, Specialty
),
Outliers AS (
    SELECT
        fa.Claim_ID,
        fa.Provider_ID,
        fa.Provider_Name,
        fa.CPT_Code,
        fa.CPT_Description,
        fa.Specialty,
        fa.Billed_Amount,
        cs.Avg_Billed,
        cs.UCL,
        fa.Fraud_Label
    FROM dbo.Fraud_Analysis fa
    JOIN CPT_Stats cs
        ON  fa.CPT_Code  = cs.CPT_Code
        AND fa.Specialty = cs.Specialty
    WHERE fa.Billed_Amount > cs.UCL
)
SELECT
    CPT_Code, CPT_Description, Specialty,
    COUNT(*) AS Outlier_Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Among_Outliers,
    CAST(AVG(Billed_Amount) AS DECIMAL(10,2)) AS Avg_Outlier_Billed,
    CAST(AVG(Avg_Billed) AS DECIMAL(10,2)) AS Expected_Avg,
    CAST(AVG(Billed_Amount/ NULLIF(Avg_Billed, 0)) AS DECIMAL(5,2)) AS Overage_Ratio
FROM Outliers
GROUP BY CPT_Code, CPT_Description, Specialty
ORDER BY Overage_Ratio DESC;

-- 08.D │ Weekend high-fraud providers (≥5 weekend claims, fraud rate > 40%)
SELECT
    Provider_ID, Provider_Name, Specialty, Provider_State,
    COUNT(*) AS Weekend_Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Weekend_Fraud,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2))  AS Weekend_Fraud_Rate_Pct,
    CAST(SUM(Billed_Amount) AS DECIMAL(14,2)) AS Weekend_Billed
FROM dbo.Fraud_Analysis
WHERE Flag_Weekend = 1
GROUP BY Provider_ID, Provider_Name, Specialty, Provider_State
HAVING COUNT(*) >= 5
   AND AVG(CAST(Fraud_Label AS FLOAT)) > 0.40
ORDER BY Weekend_Fraud_Rate_Pct DESC;


/* SECTION 09 │ INSURER & PAYER PERFORMANCE */

-- 09.A │ Comprehensive insurer exposure report
SELECT
    Insurer,
    COUNT(*) AS Total_Claims,
    COUNT(DISTINCT Provider_ID) AS Providers_Billing,
    COUNT(DISTINCT Patient_ID) AS Patients_Covered,
    CAST(SUM(Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(SUM(Paid_Amount) / 1e6 AS DECIMAL(10,3))AS Paid_M,
    CAST(SUM(Paid_Amount) / NULLIF(SUM(Billed_Amount), 0) * 100 AS DECIMAL(5,1)) AS Pay_Rate_Pct,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(CASE WHEN Fraud_Label = 1 THEN Paid_Amount ELSE 0 END) / 1e6 AS DECIMAL(10,3)) AS Fraud_Leakage_M,
    CAST(AVG(CAST(Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score
FROM dbo.Fraud_Analysis
GROUP BY Insurer
ORDER BY Fraud_Leakage_M DESC;

-- 09.B │ Fraud detection effectiveness by insurer — how much slipped through?
SELECT
    Insurer,
    SUM(CAST(Fraud_Label AS INT)) AS Total_Fraud_Claims,
    SUM(CASE WHEN Claim_Status = 'Denied' AND Fraud_Label = 1 THEN 1 ELSE 0 END) AS Caught_Denied,
    SUM(CASE WHEN Claim_Status = 'Approved' AND Fraud_Label = 1 THEN 1 ELSE 0 END) AS Slipped_Approved,
    CAST(SUM(CASE WHEN Claim_Status = 'Denied' AND Fraud_Label = 1 THEN 1 ELSE 0 END) * 100.0
         / NULLIF(SUM(CAST(Fraud_Label AS INT)), 0) AS DECIMAL(5,1)) AS Detection_Rate_Pct,
    CAST(SUM(CASE WHEN Claim_Status = 'Approved' AND Fraud_Label = 1
                  THEN Paid_Amount ELSE 0 END) / 1e3 AS DECIMAL(12,1)) AS Undetected_Paid_K
FROM dbo.Fraud_Analysis
GROUP BY Insurer
ORDER BY Undetected_Paid_K DESC;

-- 09.C │ Insurer × Specialty fraud matrix
SELECT
    Insurer,
    Specialty,
    COUNT(*) AS Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(CASE WHEN Fraud_Label = 1 THEN Paid_Amount ELSE 0 END) / 1e3 AS DECIMAL(12,1)) AS Fraud_Paid_K
FROM dbo.Fraud_Analysis
GROUP BY Insurer, Specialty
HAVING COUNT(*) > 50
ORDER BY Fraud_Rate_Pct DESC;


/* SECTION 10 │ PATIENT DEMOGRAPHY & VULNERABILITY */

-- 10.A │ Age group fraud vulnerability
SELECT
    CASE
        WHEN Patient_Age <  18 THEN '0-17  Minor'
        WHEN Patient_Age <  35 THEN '18-34 Young Adult'
        WHEN Patient_Age <  50 THEN '35-49 Middle Age'
        WHEN Patient_Age <  65 THEN '50-64 Pre-Senior'
        ELSE  '65+   Elderly'
    END AS Age_Group,
    COUNT(*) AS Claims,
    COUNT(DISTINCT Patient_ID) AS Unique_Patients,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(AVG(Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed,
    CAST(SUM(CASE WHEN Fraud_Label = 1 THEN Paid_Amount ELSE 0 END) / 1e3 AS DECIMAL(12,1)) AS Fraud_Paid_K
FROM dbo.Fraud_Analysis
GROUP BY
    CASE
        WHEN Patient_Age <  18 THEN '0-17  Minor'
        WHEN Patient_Age <  35 THEN '18-34 Young Adult'
        WHEN Patient_Age <  50 THEN '35-49 Middle Age'
        WHEN Patient_Age <  65 THEN '50-64 Pre-Senior'
        ELSE '65+ Elderly'
    END
ORDER BY Fraud_Rate_Pct DESC;

-- 10.B │ Gender fraud split
SELECT
    Patient_Gender,
    COUNT(*) AS Claims,
    COUNT(DISTINCT Patient_ID) AS Unique_Patients,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(AVG(Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed
FROM dbo.Fraud_Analysis
GROUP BY Patient_Gender;

-- 10.C │ Patients with multiple fraud encounters (ring / identity theft)
WITH DistinctFraud AS (
    SELECT DISTINCT Patient_ID, Fraud_Type 
    FROM dbo.Fraud_Analysis
),
AggregatedFraud AS (
    SELECT 
        Patient_ID,
        STRING_AGG(CAST(Fraud_Type AS VARCHAR(MAX)), ' | ') WITHIN GROUP (ORDER BY Fraud_Type) AS Fraud_Types
    FROM DistinctFraud
    GROUP BY Patient_ID
)
SELECT TOP 20
    fa.Patient_ID,
    fa.Patient_Age,
    fa.Patient_Gender,
    fa.Patient_State,
    COUNT(*) AS Total_Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    COUNT(DISTINCT fa.Provider_ID) AS Providers_Seen,
    COUNT(DISTINCT fa.Insurer) AS Insurers_Used,
    CAST(SUM(fa.Billed_Amount) / 1e3 AS DECIMAL(10,1)) AS Total_Billed_K,
    CAST(SUM(CASE WHEN fa.Fraud_Label = 1 THEN fa.Paid_Amount ELSE 0 END) / 1e3 AS DECIMAL(10,1)) AS Fraud_Paid_K,
    af.Fraud_Types
FROM dbo.Fraud_Analysis fa
LEFT JOIN AggregatedFraud af ON fa.Patient_ID = af.Patient_ID
GROUP BY fa.Patient_ID, fa.Patient_Age, fa.Patient_Gender, fa.Patient_State, af.Fraud_Types
HAVING SUM(CAST(fa.Fraud_Label AS INT)) >= 3
ORDER BY Fraud_Claims DESC;

/*  SECTION 11 │ SPECIALTY RISK STRATIFICATION */

-- 11.A │ Full specialty risk scorecard
SELECT
    fa.Specialty,
    COUNT(*) AS Total_Claims,
    COUNT(DISTINCT fa.Provider_ID) AS Providers,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2))  AS Fraud_Rate_Pct,
    CAST(SUM(fa.Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M,
    CAST(AVG(fa.Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed,
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score,
    RANK() OVER (ORDER BY AVG(CAST(fa.Fraud_Label AS FLOAT)) DESC) AS Fraud_Rate_Rank,
    RANK() OVER (ORDER BY SUM(fa.Billed_Amount) DESC) AS Revenue_Rank,
    CASE
        WHEN AVG(CAST(fa.Fraud_Label AS FLOAT)) > 0.40
         AND SUM(fa.Billed_Amount) > 1e6 THEN 'HIGH PRIORITY'
        WHEN AVG(CAST(fa.Fraud_Label AS FLOAT)) > 0.20 THEN 'MONITOR'
        ELSE 'LOW RISK'
    END AS Investigation_Priority
FROM dbo.Fraud_Analysis fa
GROUP BY fa.Specialty
ORDER BY Fraud_Rate_Rank;

-- 11.B │ Years of practice vs fraud rate — experience paradox?
SELECT
    CASE
        WHEN pr.Years_Practice <= 5  THEN '0-5 yrs'
        WHEN pr.Years_Practice <= 10 THEN '6-10 yrs'
        WHEN pr.Years_Practice <= 20 THEN '11-20 yrs'
        ELSE '20+ yrs'
    END AS Experience_Band,
    COUNT(DISTINCT pr.Provider_ID) AS Providers,
    COUNT(fa.Claim_ID) AS Claims,
    SUM(CAST(fa.Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score
FROM dbo.Provider_Registry pr
JOIN dbo.Fraud_Analysis fa ON pr.Provider_ID = fa.Provider_ID
GROUP BY
    CASE
        WHEN pr.Years_Practice <= 5  THEN '0-5 yrs'
        WHEN pr.Years_Practice <= 10 THEN '6-10 yrs'
        WHEN pr.Years_Practice <= 20 THEN '11-20 yrs'
        ELSE  '20+ yrs'
    END
ORDER BY Fraud_Rate_Pct DESC;

/* SECTION 12 │ MULTI-FLAG COMPOSITE RISK SCORING */

-- 12.A │ Flag co-occurrence matrix
SELECT
    SUM(CAST(Flag_HighValue AS INT)) AS F1_HighValue,
    SUM(CAST(Flag_Weekend AS INT)) AS F2_Weekend,
    SUM(CAST(Flag_SameDay_Volume AS INT)) AS F3_SameDay,
    SUM(CAST(Flag_UnitMismatch AS INT)) AS F4_UnitMismatch,
    SUM(CAST(Flag_Duplicate AS INT)) AS F5_Duplicate,
    SUM(CAST(Flag_HighValue AS INT) * CAST(Flag_UnitMismatch AS INT)) AS F1xF4,
    SUM(CAST(Flag_HighValue AS INT) * CAST(Flag_Duplicate AS INT)) AS F1xF5,
    SUM(CAST(Flag_Weekend AS INT) * CAST(Flag_SameDay_Volume AS INT)) AS F2xF3,
    SUM(CAST(Flag_UnitMismatch AS INT) * CAST(Flag_Duplicate AS INT)) AS F4xF5,
    SUM(CAST(Flag_HighValue AS INT) * CAST(Flag_Weekend AS INT) * CAST(Flag_Duplicate AS INT))  AS F1xF2xF5,
    SUM(CAST(Flag_HighValue AS INT) * CAST(Flag_Weekend AS INT)
        * CAST(Flag_SameDay_Volume AS INT) * CAST(Flag_UnitMismatch AS INT)
        * CAST(Flag_Duplicate AS INT)) AS All_5_Flags
FROM dbo.Fraud_Analysis;

-- 12.B │ Risk score band distribution
SELECT 
    Risk_Band,
    COUNT(*) AS Claims,
    CAST(COUNT(*) * 100.0 / 22000 AS DECIMAL(5,2)) AS Pct_Total,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(SUM(Billed_Amount) / 1e6 AS DECIMAL(10,3)) AS Billed_M
FROM dbo.Fraud_Analysis
CROSS APPLY (
    SELECT CASE 
        WHEN Fraud_Risk_Score = 0  THEN '0 Clean'
        WHEN Fraud_Risk_Score <= 20 THEN '1-20 Low'
        WHEN Fraud_Risk_Score <= 50 THEN '21-50 Moderate'
        WHEN Fraud_Risk_Score <= 70 THEN '51-70 High'
        ELSE '71-99 Critical'
    END AS Risk_Band
) AS rb
GROUP BY Risk_Band
ORDER BY MIN(Fraud_Risk_Score);

-- 12.C │ Composite risk score validation — flag count vs actual fraud rate
SELECT
    TotalFlags,
    COUNT(*) AS Claims,
    SUM(CAST(Fraud_Label AS INT)) AS Fraud_Claims,
    CAST(AVG(CAST(Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
    CAST(AVG(CAST(Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score,
    CAST(AVG(Billed_Amount) AS DECIMAL(10,2)) AS Avg_Billed
FROM (
    SELECT *,
        (CAST(Flag_HighValue AS INT)
       + CAST(Flag_Weekend AS INT)
       + CAST(Flag_SameDay_Volume AS INT)
       + CAST(Flag_UnitMismatch AS INT)
       + CAST(Flag_Duplicate AS INT)) AS TotalFlags
    FROM dbo.Fraud_Analysis
) t
GROUP BY TotalFlags
ORDER BY TotalFlags;


/* SECTION 13 │ MASTER INVESTIGATIVE PRIORITY QUEUE */

-- 13.A │ Top 50 claims — composite investigation priority score
WITH PriorityScored AS (
    SELECT
        fa.Claim_ID,
        fa.Claim_Date,
        fa.Provider_ID,
        fa.Provider_Name,
        fa.Specialty,
        fa.Provider_State,
        fa.Patient_ID,
        fa.Insurer,
        fa.Fraud_Type,
        fa.Claim_Status,
        CAST(fa.Billed_Amount AS DECIMAL(12,2)) AS Billed,
        CAST(fa.Paid_Amount AS DECIMAL(12,2)) AS Paid,
        fa.Fraud_Risk_Score,
        fa.Fraud_Label,
        pr.Is_Fraudulent,
        pr.License_Valid,
        pr.Years_Practice,
        (CAST(fa.Flag_HighValue AS INT)
         + CAST(fa.Flag_Weekend  AS INT)
         + CAST(fa.Flag_SameDay_Volume AS INT)
         + CAST(fa.Flag_UnitMismatch AS INT)
         + CAST(fa.Flag_Duplicate AS INT)) AS Total_Flags,
        (fa.Fraud_Risk_Score
         + CAST(fa.Flag_HighValue AS INT) * 10
         + CAST(fa.Flag_Duplicate AS INT) * 15
         + CAST(fa.Flag_UnitMismatch  AS INT) *  8
         + CAST(fa.Flag_SameDay_Volume AS INT) * 12
         + CAST(fa.Flag_Weekend  AS INT) *  5
         + CASE WHEN fa.Billed_Amount > 10000 THEN 20 ELSE 0 END
         + CASE WHEN pr.Is_Fraudulent = 1 THEN 25 ELSE 0 END
         + CASE WHEN pr.License_Valid = 0 THEN 15 ELSE 0 END
         + CASE WHEN fa.Fraud_Label = 1 THEN 30 ELSE 0 END
        )  AS Priority_Score
    FROM dbo.Fraud_Analysis    fa
    JOIN dbo.Provider_Registry pr ON fa.Provider_ID = pr.Provider_ID
)
SELECT TOP 50
    Priority_Score,
    Claim_ID,
    Claim_Date,
    Provider_ID,
    Provider_Name,
    Specialty,
    Provider_State,
    Patient_ID,
    Insurer,
    Fraud_Type,
    Billed,
    Paid,
    Claim_Status,
    Fraud_Risk_Score,
    Total_Flags,
    Is_Fraudulent,
    License_Valid,
    Years_Practice,
    CASE
        WHEN Priority_Score > 120 THEN ' IMMEDIATE ACTION — Refer to SIU'
        WHEN Priority_Score >  80 THEN ' URGENT — Full Audit Required'
        WHEN Priority_Score >  50 THEN ' SCHEDULE — Desk Review'
        ELSE ' MONITOR — Low Priority'
    END AS Action_Required
FROM PriorityScored
ORDER BY Priority_Score DESC;

-- 13.B │ Provider intervention queue — who to audit first
WITH ProviderPriority AS (
    SELECT
        fa.Provider_ID,
        fa.Provider_Name,
        fa.Specialty,
        fa.Provider_State,
        COUNT(*) AS Total_Claims,
        SUM(CAST(fa.Fraud_Label AS INT))  AS Fraud_Claims,
        CAST(AVG(CAST(fa.Fraud_Label AS FLOAT)) * 100 AS DECIMAL(5,2)) AS Fraud_Rate_Pct,
        CAST(AVG(CAST(fa.Fraud_Risk_Score AS FLOAT)) AS DECIMAL(5,1)) AS Avg_Risk_Score,
        CAST(SUM(fa.Billed_Amount) / 1e3 AS DECIMAL(12,1)) AS Billed_K,
        SUM(CAST(fa.Flag_UnitMismatch AS INT)) AS Unit_Mismatches,
        SUM(CAST(fa.Flag_Duplicate AS INT)) AS Dup_Flags
    FROM dbo.Fraud_Analysis fa
    GROUP BY fa.Provider_ID, fa.Provider_Name, fa.Specialty, fa.Provider_State
)
SELECT TOP 25
    ROW_NUMBER() OVER (ORDER BY pp.Fraud_Rate_Pct DESC,
                                pp.Avg_Risk_Score  DESC) AS Queue_Position,
    pp.Provider_ID,
    pp.Provider_Name,
    pp.Specialty,
    pp.Provider_State,
    pp.Total_Claims,
    pp.Fraud_Claims,
    pp.Fraud_Rate_Pct,
    pp.Avg_Risk_Score,
    pp.Billed_K,
    pp.Unit_Mismatches,
    pp.Dup_Flags,
    pr.Is_Fraudulent,
    pr.License_Valid,
    pr.Network_Status,
    CASE
        WHEN pr.Is_Fraudulent = 1 AND pr.License_Valid = 1
             THEN 'LICENSE REVOCATION + CRIMINAL REFERRAL'
        WHEN pp.Fraud_Rate_Pct >= 80
             THEN 'IMMEDIATE SIU INVESTIGATION'
        WHEN pp.Fraud_Rate_Pct >= 50
             THEN ' FULL AUDIT — Billing Review'
        ELSE 'ENHANCED MONITORING'
    END  AS Intervention
FROM ProviderPriority pp
JOIN dbo.Provider_Registry pr ON pp.Provider_ID = pr.Provider_ID
ORDER BY pp.Fraud_Rate_Pct DESC, pp.Avg_Risk_Score DESC;



