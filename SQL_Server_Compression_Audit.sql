/********************************************************************************************
 Script:   SQL_Server_Compression_Audit.sql
 Author:   MS
 Purpose:  Audit table compression settings across all user databases.

 Description:
   - Iterates through all user databases (excludes system DBs: master, model, msdb)
   - Captures compression type (NONE, ROW, PAGE, COLUMNSTORE, etc.) per table
   - Includes row counts and partition information
   - Useful for capacity planning, performance tuning, and compliance reporting

 Usage:
   - Run in SQL Server Management Studio (SSMS)
   - Results will show each table’s compression method and row count
   - Helps DBAs quickly identify which tables are (or are not) using compression
********************************************************************************************/

USE master
GO

-- Drop temp table if it already exists
IF OBJECT_ID('tempdb..#CompressionDetails') IS NOT NULL
    DROP TABLE #CompressionDetails
GO

-- Create temp table to hold compression info
CREATE TABLE #CompressionDetails
(
    DBName NVARCHAR(128),
    TableName NVARCHAR(128),
    RowCnt BIGINT,
    DataCompressionDescription NVARCHAR(60),
    PartitionID BIGINT
)

-- Populate table with compression details from all user DBs
INSERT INTO #CompressionDetails
EXECUTE sp_msforeachdb '
USE [?]
IF db_name(db_id()) NOT IN (''master'', ''model'', ''msdb'')
BEGIN
    SELECT 
        DBName = ''?'',
        TableName = OBJECT_NAME(p.object_id, DB_ID()),
        rows,
        p.data_compression_desc,
        p.partition_id
    FROM sys.partitions p WITH (NOLOCK)
    JOIN sys.objects o WITH (NOLOCK) 
        ON p.object_id = o.object_id
    WHERE o.type = ''U''   -- user tables only
END
'

-- Marker for output readability
PRINT '-- CompressionDetails'

-- Return final ordered results
SELECT *
FROM #CompressionDetails
ORDER BY DBName, DataCompressionDescription, TableName
