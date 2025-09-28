USE [YourDatabase]  -- Replace with the database you want
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_listu]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        spid = er.session_id,
        ecid = er.request_id,
        logical_reads = er.logical_reads,
        [Database] = DB_NAME(er.database_id),
        [User] = sp.nt_username,
        [Status] = er.status,
        [Wait] = er.wait_type,
        [IndividualQuery] = SUBSTRING(
            qt.text,
            CASE WHEN er.statement_start_offset >= 0 THEN er.statement_start_offset / 2 ELSE 0 END + 1,
            CASE 
                WHEN er.statement_end_offset = -1 THEN LEN(qt.text)
                ELSE (er.statement_end_offset - er.statement_start_offset) / 2
            END
        ),
        [ParentQuery] = qt.text,
        Program = sp.program_name,
        Hostname = sp.hostname,
        NT_Domain = sp.nt_domain,
        Start_Time = sp.login_time
    FROM sys.dm_exec_requests er
    INNER JOIN sys.sysprocesses sp
        ON er.session_id = sp.spid
    CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) AS qt
    WHERE er.session_id > 50           -- Ignore system SPIDs
      AND er.session_id <> @@SPID      -- Ignore current session
    ORDER BY er.session_id, er.request_id;
END
GO
