-- =====================================================
-- Snowpipe Auto-Retry System - Cleanup Script
-- =====================================================


USE ROLE ACCOUNTADMIN;

-- =====================================================
-- CONFIRMATION CHECK
-- =====================================================

/*
BEFORE RUNNING THIS SCRIPT:

This script will PERMANENTLY DELETE:
- Database: snowpipe_monitor_demo (including all tables and data)
- Warehouse: monitor_wh
- User: n8n_monitor
- Storage integration: s3_integration

Are you sure you want to proceed? 
If yes, uncomment the sections below and run them one at a time.
*/

-- =====================================================
-- 1. PAUSE SNOWPIPE (Recommended before cleanup)
-- =====================================================

/*
ALTER PIPE snowpipe_monitor_demo.raw.call_logs_pipe SET PIPE_EXECUTION_PAUSED = TRUE;
SELECT SYSTEM$PIPE_STATUS('snowpipe_monitor_demo.raw.call_logs_pipe');
*/

-- =====================================================
-- 2. DROP PIPE
-- =====================================================

/*
DROP PIPE IF EXISTS snowpipe_monitor_demo.raw.call_logs_pipe;
*/

-- =====================================================
-- 3. DROP STAGE AND FILE FORMAT
-- =====================================================

/*
DROP STAGE IF EXISTS snowpipe_monitor_demo.raw.s3_external_stage;
DROP FILE FORMAT IF EXISTS snowpipe_monitor_demo.raw.strict_csv;
*/

-- =====================================================
-- 4. DROP TABLES
-- =====================================================

/*
DROP TABLE IF EXISTS snowpipe_monitor_demo.raw.staging_call_logs;
DROP TABLE IF EXISTS snowpipe_monitor_demo.raw.snowpipe_failure_logs;
*/

-- =====================================================
-- 5. DROP STORAGE INTEGRATION
-- =====================================================

/*
DROP STORAGE INTEGRATION IF EXISTS s3_integration;
*/

-- =====================================================
-- 6. DROP SCHEMA
-- =====================================================

/*
DROP SCHEMA IF EXISTS snowpipe_monitor_demo.raw;
*/

-- =====================================================
-- 7. DROP DATABASE
-- =====================================================

/*
DROP DATABASE IF EXISTS snowpipe_monitor_demo;
*/

-- =====================================================
-- 8. DROP WAREHOUSE
-- =====================================================

/*
DROP WAREHOUSE IF EXISTS monitor_wh;
*/

-- =====================================================
-- 9. DROP USER
-- =====================================================

/*
DROP USER IF EXISTS n8n_monitor;
*/

-- =====================================================
-- 10. VERIFY CLEANUP
-- =====================================================

/*
-- Check if objects are removed
SHOW DATABASES LIKE 'snowpipe_monitor_demo';
SHOW WAREHOUSES LIKE 'monitor_wh';
SHOW USERS LIKE 'n8n_monitor';
SHOW INTEGRATIONS;

SELECT 'Cleanup completed - all objects removed' AS status;
*/

-- =====================================================
-- PARTIAL CLEANUP OPTIONS
-- =====================================================

-- Option A: Clear data but keep structure
/*
TRUNCATE TABLE snowpipe_monitor_demo.raw.staging_call_logs;
TRUNCATE TABLE snowpipe_monitor_demo.raw.snowpipe_failure_logs;
SELECT 'Data cleared - structure intact' AS status;
*/

-- Option B: Reset retry logs only
/*
TRUNCATE TABLE snowpipe_monitor_demo.raw.snowpipe_failure_logs;
SELECT 'Retry logs cleared' AS status;
*/

-- Option C: Pause pipe temporarily (without deleting)
/*
ALTER PIPE snowpipe_monitor_demo.raw.call_logs_pipe SET PIPE_EXECUTION_PAUSED = TRUE;
SELECT 'Pipe paused - can be resumed later' AS status;

-- To resume later:
-- ALTER PIPE snowpipe_monitor_demo.raw.call_logs_pipe SET PIPE_EXECUTION_PAUSED = FALSE;
*/

-- =====================================================
-- AWS CLEANUP REMINDER
-- =====================================================

/*
After running this cleanup script, also clean up AWS resources:

1. S3 Bucket:
   - Delete objects in bucket
   - Delete bucket (or keep for other uses)

2. SNS Topic:
   - Delete topic: snowpipe-s3-events

3. IAM Role:
   - Delete role: snowflake-s3-access-role
   - Delete attached policies

4. S3 Event Notifications:
   - Remove event notification configuration from bucket
*/

-- =====================================================
-- N8N CLEANUP REMINDER
-- =====================================================

/*
In n8n:
1. Deactivate workflow
2. Delete or archive workflow
3. Remove Snowflake credential
*/
