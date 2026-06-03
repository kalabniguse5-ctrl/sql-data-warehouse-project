/****************************************************************************************
 Script Name : Setup_DataWarehouse_Medallion.sql

 Purpose:
     - Ensures the DataWarehouse database exists
     - Creates Medallion Architecture schemas:
         * bronze  (raw data layer)
         * silver  (cleaned/transform layer)
         * gold    (business/reporting layer)

 Warning:
     - Running this script in production without review may overwrite existing setup logic.
     - This script only creates database/schemas; it does NOT drop anything.
     - Always test in a development environment first.

 Author : Your Name
 Date   : 2026-06-03
****************************************************************************************/


/* ============================================================================
   STEP 1: CHECK AND CREATE DATABASE
============================================================================ */

IF DB_ID('DataWarehouse') IS NULL
BEGIN
    CREATE DATABASE DataWarehouse;
END
GO


/* Switch context to DataWarehouse */
USE DataWarehouse;
GO


/* ============================================================================
   STEP 2: CREATE BRONZE SCHEMA (RAW DATA LAYER)
============================================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze')
BEGIN
    EXEC('CREATE SCHEMA bronze');
END
GO

-- Bronze layer created for raw ingested data


/* ============================================================================
   STEP 3: CREATE SILVER SCHEMA (CLEANED DATA LAYER)
============================================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
BEGIN
    EXEC('CREATE SCHEMA silver');
END
GO

-- Silver layer created for cleaned and standardized data


/* ============================================================================
   STEP 4: CREATE GOLD SCHEMA (BUSINESS DATA LAYER)
============================================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
BEGIN
    EXEC('CREATE SCHEMA gold');
END
GO

-- Gold layer created for reporting and analytics


/* ============================================================================
   STEP 5: VALIDATION QUERY
============================================================================ */

SELECT 
    name AS SchemaName
FROM sys.schemas
WHERE name IN ('bronze', 'silver', 'gold');
GO
