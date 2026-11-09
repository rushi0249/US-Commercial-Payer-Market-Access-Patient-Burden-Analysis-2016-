CREATE DATABASE IQVIA_Project;
GO
USE IQVIA_Project;
GO

-- Import filtered tables from SQLite Linked Server into SQL Server
SELECT * INTO PlanAttributes 
FROM OPENQUERY(SQLITE_DB, 'SELECT PlanId, StateCode, MetalLevel, PlanType, MarketCoverage, DentalOnlyPlan FROM PlanAttributes WHERE BusinessYear = 2016');

SELECT * INTO BenefitsCostSharing 
FROM OPENQUERY(SQLITE_DB, 'SELECT PlanId, BenefitName, CopayInnTier1, CoinsInnTier1 FROM BenefitsCostSharing WHERE BusinessYear = 2016 AND BenefitName IN (''Generic Drugs'', ''Preferred Brand Drugs'', ''Specialty Drugs'')');

SELECT * INTO Rate 
FROM OPENQUERY(SQLITE_DB, 'SELECT PlanId, IndividualRate FROM Rate WHERE BusinessYear = 2016 AND Age = ''40''');
GO

-- Fix ntext columns imported from SQLite so joins and grouping work properly
ALTER TABLE PlanAttributes ALTER COLUMN PlanId VARCHAR(50);
ALTER TABLE PlanAttributes ALTER COLUMN StateCode VARCHAR(10);
ALTER TABLE PlanAttributes ALTER COLUMN MetalLevel VARCHAR(50);
ALTER TABLE PlanAttributes ALTER COLUMN PlanType VARCHAR(50);
ALTER TABLE PlanAttributes ALTER COLUMN MarketCoverage VARCHAR(50);
ALTER TABLE PlanAttributes ALTER COLUMN DentalOnlyPlan VARCHAR(10);

ALTER TABLE BenefitsCostSharing ALTER COLUMN PlanId VARCHAR(50);
ALTER TABLE BenefitsCostSharing ALTER COLUMN BenefitName VARCHAR(100);
ALTER TABLE BenefitsCostSharing ALTER COLUMN CopayInnTier1 VARCHAR(255);
ALTER TABLE BenefitsCostSharing ALTER COLUMN CoinsInnTier1 VARCHAR(255);

ALTER TABLE Rate ALTER COLUMN PlanId VARCHAR(50);
GO

-- Create the main view for drug access analysis
CREATE OR ALTER VIEW vw_pharma_access AS
SELECT 
    p.PlanId,
    p.StateCode,
    p.MetalLevel,
    p.PlanType,
    ROUND(AVG(CAST(r.IndividualRate AS FLOAT)), 2) AS monthly_premium,
    d.BenefitName AS drug_tier,
    d.CopayInnTier1 AS raw_copay,
    d.CoinsInnTier1 AS raw_coinsurance,
    CASE 
        WHEN d.CoinsInnTier1 LIKE '%30%' OR d.CoinsInnTier1 LIKE '%40%' OR d.CoinsInnTier1 LIKE '%50%' 
            THEN 'High Barrier (Coinsurance)'
        WHEN d.CopayInnTier1 LIKE '%No Charge%' OR d.CopayInnTier1 LIKE '%$0%' OR d.CopayInnTier1 LIKE '%$10%' 
            THEN 'Favorable Access (Low Copay)'
        ELSE 'Moderate Barrier'
    END AS access_tier
FROM PlanAttributes p
INNER JOIN BenefitsCostSharing d 
    ON LEFT(p.PlanId, 14) = LEFT(d.PlanId, 14)
INNER JOIN Rate r 
    ON LEFT(p.PlanId, 14) = LEFT(r.PlanId, 14)
WHERE p.MarketCoverage = 'Individual'
  AND p.DentalOnlyPlan = 'No'
GROUP BY 
    p.PlanId, 
    p.StateCode, 
    p.MetalLevel, 
    p.PlanType, 
    d.BenefitName, 
    d.CopayInnTier1, 
    d.CoinsInnTier1;
GO
