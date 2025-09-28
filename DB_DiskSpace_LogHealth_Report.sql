/********************************************************************************************
 Script:   DB_DiskSpace_LogHealth_Report.sql
 Author:  irphanalishaik
 Purpose:  Generate a comprehensive Database Disk Space and Transaction Log Health Report
           for all databases in a SQL Server instance.

 Description:
   - Collects database file (MDF, NDF, LDF) information across all databases
   - Reports file sizes, used/available space, growth settings, and next growth increment
   - Captures I/O statistics (reads, writes, stalls)
   - Gathers Virtual Log File (VLF) details using DBCC LOGINFO
   - Identifies open long-running transactions that prevent log truncation
   - Enriches with database properties (recovery model, page verify option, etc.)
   - Collects disk-level details (volume, filesystem, available/total size)

 Usage:
   - Run in SQL Server Management Studio (SSMS) as sysadmin or with VIEW SERVER STATE permission
   - Output helps DBAs monitor space, performance, and log health proactively

********************************************************************************************/

SET NOCOUNT ON
GO

USE master
GO

/* Drop temp tables if they exist to avoid conflicts */
IF object_id('tempdb..#loginfo') IS NOT NULL DROP TABLE #loginfo
IF object_id('tempdb..#LogSummary') IS NOT NULL DROP TABLE #LogSummary
IF object_id('tempdb..#DBInfoFull') IS NOT NULL DROP TABLE #DBInfoFull
IF object_id('tempdb..#DatabaseFiles') IS NOT NULL DROP TABLE #DatabaseFiles
GO

/* Temporary table to hold database file information */
CREATE TABLE #DatabaseFiles
(
    DBName                  NVARCHAR(128),
    DatabaseID              INT,
    FileID                  INT,
    FGName                  NVARCHAR(128),
    IsDefaultFG             BIT,
    LogicalName             NVARCHAR(128),
    FilePath                NVARCHAR(260),
    SizeInMB                NUMERIC(29,7),
    Growth                  VARCHAR(13),
    AverageReadStallMS      BIGINT,
    AverageWriteStallMS     BIGINT,
    AverageIOStallMS        BIGINT,
    num_of_reads            BIGINT,
    num_of_bytes_read       BIGINT,
    io_stall_read_ms        BIGINT,
    num_of_writes           BIGINT,
    num_of_bytes_written    BIGINT,
    io_stall_write_ms       BIGINT,
    io_stall                BIGINT,
    size_on_disk_bytes      BIGINT,
    IDCol                   INT IDENTITY(1,1) PRIMARY KEY CLUSTERED, 
    CreationDate            DATETIME DEFAULT(getdate()), 
    MaxSizeMB               NUMERIC(20,7),
    UsedSpaceMB             NUMERIC(20,7),
    AvailableSpaceMBBeforeGrowth NUMERIC(20,7)
)

/* Populate #DatabaseFiles with data from all databases */
INSERT INTO #DatabaseFiles
(
    DBName, DatabaseID, FileID, FGName, IsDefaultFG, LogicalName, FilePath,
    SizeInMB, Growth, AverageReadStallMS, AverageWriteStallMS, AverageIOStallMS,
    num_of_reads, num_of_bytes_read, io_stall_read_ms,
    num_of_writes, num_of_bytes_written, io_stall_write_ms,
    io_stall, size_on_disk_bytes, MaxSizeMB, UsedSpaceMB, AvailableSpaceMBBeforeGrowth
)
EXECUTE sp_msforeachdb N'
USE [?]
SELECT 
    DBName = db_name(db_id(''?'')), 
    DB_ID(),
    mf.file_id,
    FGName = f.name, 
    IsDefaultFG = f.is_default, 
    LogicalName = mf.name,
    FilePath = physical_name,
    SizeInMB = (size*8.0)/1024.0, 
    Growth = CASE WHEN is_percent_growth = 1 
                  THEN CAST(growth AS VARCHAR(10)) + '' %'' 
                  ELSE CAST((growth/128) AS VARCHAR(10)) + '' MB'' END, 
    AverageReadStallMS = fs.io_stall_read_ms/(fs.num_of_reads+1),
    AverageWriteStallMS = fs.io_stall_write_ms/(fs.num_of_writes+1),
    AverageIOStallMS = io_stall/(num_of_reads + num_of_writes + 1),
    fs.num_of_reads,
    fs.num_of_bytes_read,
    fs.io_stall_read_ms,
    fs.num_of_writes,
    fs.num_of_bytes_written,
    fs.io_stall_write_ms,
    fs.io_stall,
    fs.size_on_disk_bytes,
    MaxSizeGB = CASE WHEN mf.max_size > 0 THEN ((mf.max_size/128.0)) ELSE 0 END, 
    CAST(CASE mf.type 
            WHEN 2 THEN mf.size * CONVERT(float,8)  
            WHEN 1 THEN CAST(FILEPROPERTY(mf.name, ''SpaceUsed'') AS float)* CONVERT(float,8) 
            ELSE dfs.allocated_extent_page_count*convert(float,8) END AS float)/1024.0 AS [UsedSpace], 
    ((size*8.0)/1024.0) - 
        CAST(CASE mf.type 
            WHEN 2 THEN mf.size * CONVERT(float,8)  
            WHEN 1 THEN CAST(FILEPROPERTY(mf.name, ''SpaceUsed'') AS float)* CONVERT(float,8) 
            ELSE dfs.allocated_extent_page_count*convert(float,8) END AS float)/1024.0
FROM sys.database_files mf
LEFT JOIN sys.filegroups f on mf.data_space_id = f.data_space_id
JOIN sys.dm_io_virtual_file_stats(db_id(''?''), NULL) fs ON fs.file_id = mf.file_id
LEFT OUTER JOIN sys.dm_db_file_space_usage dfs 
    ON dfs.database_id = db_id() AND dfs.file_id = mf.file_id
'

/* Calculate next growth size in MB */
ALTER TABLE #DatabaseFiles ADD NextGrowthSizeMB DECIMAL(12,2)
UPDATE #DatabaseFiles
SET NextGrowthSizeMB = 
    CAST((CASE 
        WHEN Growth LIKE '%MB' THEN LEFT(Growth,CHARINDEX(' ', Growth)) 
        ELSE (CAST(LEFT(Growth,CHARINDEX(' ', Growth)) AS DECIMAL(4,2))/100.0)*SizeInMB
    END) AS DECIMAL(12,2))

/* Prepare #loginfo to capture DBCC LOGINFO output */
CREATE TABLE #loginfo (fld1 INT)

/* Adjust loginfo schema depending on SQL Server version */
DECLARE @MajorVersion SMALLINT
SET @MajorVersion = LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)))-1)

IF @MajorVersion >= 11
BEGIN
    ALTER TABLE #loginfo ADD recoveryunitid INT, fileid VARCHAR(255), filesize VARCHAR(255),
        startoffset VARCHAR(255), fseqno VARCHAR(255), status VARCHAR(255), 
        parity VARCHAR(255), createlsn VARCHAR(255)
END
ELSE
BEGIN
    ALTER TABLE #loginfo ADD fileid VARCHAR(255), filesize VARCHAR(255),
        startoffset VARCHAR(255), fseqno VARCHAR(255), STATUS VARCHAR(255),
        parity VARCHAR(255), createlsn VARCHAR(255)
END
ALTER TABLE #loginfo DROP COLUMN fld1

/* Table to summarize log info per database */
SELECT TOP(0) * INTO #LogSummary FROM #loginfo
ALTER TABLE #LogSummary ADD DBName SYSNAME

/* Collect VLF info for each database */
EXECUTE sp_msforeachdb N'
TRUNCATE TABLE #LogInfo
USE [?]
INSERT INTO #LogInfo EXECUTE(''DBCC LOGINFO'')
INSERT INTO #LogSummary SELECT *, ''?'' FROM #loginfo
'

/* Final dataset with DB + file + log + config info */
SELECT 
    df.*, 
    AvailableFileGrowthMBBeforeLimit = CASE WHEN MaxSizeMB > 0 THEN MaxSizeMB - UsedSpaceMB ELSE 0 END,
    PageVerifyOption = d.page_verify_option_desc,
    RCSIOn = d.is_read_committed_snapshot_on,
    DBStateDesc = d.state_desc, 
    AutoCloseOn = d.is_auto_close_on, 
    AutoShrinkOn = d.is_auto_shrink_on, 
    IsReadOnly = d.is_read_only,
    UserAccessDesc = d.user_access_desc, 
    RecoveryModelDesc = d.recovery_model_desc,
    DBOwner = suser_sname(owner_sid), 
    LogReuseWaitDesc = d.log_reuse_wait_desc, 
    IsStandbyMode = d.is_in_standby,
    IsCleanlyShutdown = d.is_cleanly_shutdown,
    VLFCount = (SELECT COUNT(*) FROM #LogSummary ls WHERE ls.DBName = d.name), 
    ActiveTranStartTime = (
        SELECT MIN(last_request_start_time)
        FROM sys.dm_exec_sessions s
        WHERE open_transaction_count > 0 
          AND db_name(database_id) = d.name 
          AND s.is_user_process = 1 
          AND s.session_id <> @@SPID
    )
INTO #DBInfoFull
FROM #DatabaseFiles df
JOIN sys.databases d ON df.DatabaseID = d.database_id

/* Try to add disk-level information if supported */
BEGIN TRY
    IF EXISTS(SELECT * FROM sys.dm_os_volume_stats(1,1))
    BEGIN
        ALTER TABLE #DBInfoFull
        ADD VolumeMountPoint VARCHAR(200), VolumeID VARCHAR(200),
            LogicalVolumeName VARCHAR(200), FileSystem VARCHAR(200),
            TotalGB DECIMAL(18,2), AvailableGB DECIMAL(18,2), IsCompressed BIT

        UPDATE f
        SET 
            VolumeMountPoint = x.volume_mount_point,
            VolumeID = x.volume_id,
            LogicalVolumeName = x.logical_volume_name,
            FileSystem = x.file_system_type,
            TotalGB = x.total_bytes/1024.0/1024.0/1024.0,
            AvailableGB = x.available_bytes/1024.0/1024.0/1024.0,
            IsCompressed = x.is_compressed
        FROM #DBInfoFull f
        CROSS APPLY sys.dm_os_volume_stats(f.DatabaseID, f.FileID) x
    END
END TRY
BEGIN CATCH
    -- Fail gracefully if volume stats DMV not available
END CATCH

/* Final Output */
PRINT '-- DBDiskSpace'
SELECT 
    DBName, LogicalName, MaxSizeMB, UsedSpaceMB, 
    AvailableFileGrowthMBBeforeLimit, AvailableSpaceMBBeforeGrowth,  
    TotalGB, AvailableGB, SizeInMB, LogReuseWaitDesc, VolumeMountPoint,
    RecoveryModelDesc, Growth, NextGrowthSizeMB, ActiveTranStartTime, 
    ActiveTranDurationMinutes = DATEDIFF(MINUTE, ActiveTranStartTime, GETDATE())
FROM #DBInfoFull
