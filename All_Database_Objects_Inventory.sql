/********************************************************************************************
 Script:   All_Database_Objects_Inventory.sql
 Author:   irphanalishaik
 Purpose:  Collect a list of all objects (tables, views, stored procedures, etc.)
           from every database in the SQL Server instance.

 Description:
   - Creates a temp table (#Objects) to hold consolidated object info
   - Loops through each database using sp_msforeachdb
   - Inserts results from sys.objects along with the database name
   - Final output provides a full inventory of all objects across databases

 Usage:
   - Run in SQL Server Management Studio (SSMS)
   - Useful for auditing, documentation, or migration assessments
********************************************************************************************/

SET NOCOUNT ON   -- Suppress row count messages for cleaner output

/* Drop temp table if it already exists */
IF OBJECT_ID('tempdb..#Objects') IS NOT NULL
    DROP TABLE #Objects

/* Create empty temp table based on sys.objects structure, plus DBName column */
SELECT TOP(0) 
    DBName = DB_NAME(DB_ID()), 
    * 
INTO #Objects
FROM sys.objects

/* Insert objects from all databases into #Objects */
INSERT INTO #Objects
EXECUTE sp_msforeachdb 'USE [?]
SELECT DBName = DB_NAME(DB_ID()), *
FROM sys.objects'

/* Print marker for readability */
PRINT '-- AllObjects'

/* Final output: consolidated list of objects across all DBs */
SELECT *
FROM #Objects
