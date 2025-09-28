SELECT 
    er.session_id,         -- ID of the session (SPID) running the request
    er.status,             -- Current status (running, suspended, etc.)
    er.command,            -- Command being executed (SELECT, INSERT, BACKUP, etc.)
    er.wait_type,          -- If waiting, the type of wait (e.g., LCK_M_S, PAGEIOLATCH_SH, CXPACKET)
    er.last_wait_type,     -- The last wait encountered
    er.wait_resource,      -- The specific resource being waited on (e.g., which lock/page)
    er.wait_time           -- Duration of the current wait
FROM sys.dm_exec_requests er
INNER JOIN sys.dm_exec_sessions es
    ON er.session_id = es.session_id
   AND es.is_user_process = 1        -- Filters only user sessions (ignores system tasks)
   AND er.session_id <> @@SPID       -- Excludes your own current session
