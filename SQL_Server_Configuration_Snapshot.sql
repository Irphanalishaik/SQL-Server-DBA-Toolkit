/********************************************************************************************
 Script:   SQL_Server_Configuration_Snapshot.sql
 Author:   MS
 Purpose:  Display current SQL Server configuration settings.

 Description:
   - Uses sys.configurations to retrieve server-level configuration options
   - Equivalent to running "sp_configure" but easier to query programmatically
   - Helps DBAs check instance-level settings for compliance, tuning, or auditing

 Usage:
   - Run in SQL Server Management Studio (SSMS)
   - Output includes:
       * name          = configuration option name
       * value_in_use  = active value currently applied
********************************************************************************************/

SET NOCOUNT ON   -- Suppress row count messages for cleaner output

/* Print marker for clarity in multi-script runs */
PRINT '==== sp_configure'

/* Query all SQL Server configuration options currently in use */
SELECT 
    name, 
    value_in_use
FROM sys.configurations
