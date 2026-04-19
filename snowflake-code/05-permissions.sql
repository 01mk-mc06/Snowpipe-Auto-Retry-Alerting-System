-- =====================================================
-- Snowpipe Auto-Retry System - Permissions Setup
-- =====================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

-- =====================================================
-- 1. CREATE N8N MONITORING USER
-- =====================================================
-- NOTE: Replace STRONG_PASSWORD_HERE with a secure password

CREATE USER IF NOT EXISTS n8n_monitor
  PASSWORD = 'STRONG_PASSWORD_HERE'
  DEFAULT_WAREHOUSE = monitor_wh
  DEFAULT_NAMESPACE = snowpipe_monitor_demo.raw
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'Service account for n8n monitoring workflow';

-- =====================================================
-- 2. GRANT DATABASE AND SCHEMA PERMISSIONS
-- =====================================================

-- Database access
GRANT USAGE ON DATABASE snowpipe_monitor_demo TO USER n8n_monitor;

-- Schema access
GRANT USAGE ON SCHEMA snowpipe_monitor_demo.raw TO USER n8n_monitor;

-- Warehouse access
GRANT USAGE ON WAREHOUSE monitor_wh TO USER n8n_monitor;

-- =====================================================
-- 3. GRANT TABLE PERMISSIONS
-- =====================================================

-- Read access to staging table (for COPY_HISTORY queries)
GRANT SELECT ON TABLE snowpipe_monitor_demo.raw.staging_call_logs TO USER n8n_monitor;

-- Read/Write access to failure logs
GRANT SELECT, INSERT, UPDATE ON TABLE snowpipe_monitor_demo.raw.snowpipe_failure_logs TO USER n8n_monitor;

-- =====================================================
-- 4. GRANT STAGE AND FILE FORMAT PERMISSIONS
-- =====================================================

GRANT USAGE ON STAGE snowpipe_monitor_demo.raw.s3_external_stage TO USER n8n_monitor;
GRANT USAGE ON FILE FORMAT snowpipe_monitor_demo.raw.strict_csv TO USER n8n_monitor;
GRANT USAGE ON INTEGRATION s3_integration TO USER n8n_monitor;

-- =====================================================
-- 5. GRANT PIPE PERMISSIONS
-- =====================================================

-- Allow pipe operations (refresh)
GRANT OPERATE ON PIPE snowpipe_monitor_demo.raw.call_logs_pipe TO USER n8n_monitor;

-- =====================================================
-- 6. GRANT COPY_HISTORY ACCESS
-- =====================================================

-- Required to query INFORMATION_SCHEMA.COPY_HISTORY
GRANT IMPORTED PRIVILEGES ON DATABASE snowflake TO USER n8n_monitor;

-- =====================================================
-- 7. VERIFY PERMISSIONS
-- =====================================================

-- Show grants to user
SHOW GRANTS TO USER n8n_monitor;

-- =====================================================
-- 8. TEST USER ACCESS (Optional)
-- =====================================================

/*
To test the n8n_monitor user:

1. Open a new worksheet or session
2. Run the following commands:

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE monitor_wh;

-- Test COPY_HISTORY access
SELECT * 
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -1, CURRENT_TIMESTAMP())
))
LIMIT 10;

-- Test pipe operation
SELECT SYSTEM$PIPE_STATUS('call_logs_pipe');

-- Test retry log access
SELECT * FROM snowpipe_failure_logs LIMIT 10;

If all queries succeed, the user is configured correctly.
*/
