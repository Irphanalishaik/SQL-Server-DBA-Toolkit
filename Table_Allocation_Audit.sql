/********************************************************************************************
 Script:   Table_Allocation_Audit.sql
 Author:  MS
 Purpose:  Audit table-level space allocation across all user databases.

 Description:
   - Collects storage allocation information for all user tables in all databases
   - Captures total, used, and data pages, row counts, and partition counts
   - Useful for monitoring large tables, partitioned tables, and TempDB usage
   - Helps DBAs identify tables consuming excessive space

 Usage:
   - Run in SQL Server Management Studio (SSMS)
   - Outputs results to a temporary table #Results
   - Requires appropriate permissions (VIEW DATABASE STATE or sysadmin)
********************************************************************************************/

SET NOCOUNT ON   -- Suppress row count messages

-- Drop temp table if it exists
IF OBJECT_ID('tempdb..#Results') IS NOT NULL
    DROP TABLE #Results
GO

-- Create temp table to hold allocation results
CREATE TABLE #Results
(
    DBName sysname,         -- Database name
    ObjectName sysname,     -- Table name
    TypeDesc varchar(400),  -- Allocation type (IN_ROW_DATA, LOB_DATA, ROW_OVERFLOW_DATA)
    TotalPages INT,         -- Total pages allocated
    UsedPages INT,          -- Pages currently in use
    DataPages INT,          -- Pages used by actual data
    RowCnt INT,             -- Number of rows
    PartitionCount INT      -- Number of partitions
)

-- Populate temp table with allocation info from all user databases
INSERT INTO #Results
EXECUTE sp_msforeachdb N'
USE [?]
SELECT 
    databasename = DB_NAME(),
    ObjectName = o.name, 
    u.type_desc,
    TotalPages = SUM(total_pages),
    UsedPages = SUM(used_pages),
    DataPages = SUM(data_pages),
    RowCnt = SUM(rows),
    PartitionCount = COUNT(DISTINCT partition_number)
FROM sys.allocation_units u WITH (NOLOCK)
JOIN sys.partitions p WITH (NOLOCK) 
    ON u.container_id = CASE 
        WHEN u.type IN (1,3) THEN p.hobt_id 
        ELSE partition_id 
       END
JOIN sys.objects o WITH (NOLOCK) 
    ON p.object_id = o.object_id
WHERE o.type = ''U''   -- User tables only
GROUP BY o.name, u.type_desc
'

-- Marker for clarity
PRINT '-- TableAllocations'

-- Return results ordered by largest tables first
SELECT *
FROM #Results
ORDER BY RowCnt DESC
