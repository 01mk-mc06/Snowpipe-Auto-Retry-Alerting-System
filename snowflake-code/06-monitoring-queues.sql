-- =====================================================
-- Snowpipe Auto-Retry System - Monitoring Queries
-- =====================================================

USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

-- =====================================================
-- 1. CHECK RECENT LOAD HISTORY
-- =====================================================

-- View all load attempts (last 24 hours)
SELECT 
  file_name,
  status,
  row_count,
  error_count,
  first_error_message,
  last_load_time,
  DATEDIFF('minute', last_load_time, CURRENT_TIMESTAMP()) as minutes_ago,
  pipe_name
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
))
ORDER BY last_load_time DESC;

-- =====================================================
-- 2. CHECK FAILED LOADS ONLY
-- =====================================================

SELECT 
  file_name,
  status,
  error_count,
  first_error_message,
  first_error_line_number,
  first_error_character_pos,
  first_error_column_name,
  last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -7, CURRENT_TIMESTAMP())
))
WHERE status = 'LOAD_FAILED'
ORDER BY last_load_time DESC;

-- =====================================================
-- 3. CHECK RETRY ATTEMPTS
-- =====================================================

-- View all retry attempts
SELECT 
  pipe_name,
  file_name,
  retry_count,
  error_message,
  failure_time,
  notified,
  DATEDIFF('minute', failure_time, CURRENT_TIMESTAMP()) as minutes_since_failure
FROM snowpipe_failure_logs
ORDER BY failure_time DESC;

-- =====================================================
-- 4. TRACK MULTIPLE RETRY ATTEMPTS FOR SAME FILE
-- =====================================================

WITH numbered_attempts AS (
  SELECT 
    file_name,
    status,
    last_load_time,
    error_count,
    first_error_message,
    ROW_NUMBER() OVER (PARTITION BY file_name ORDER BY last_load_time) as attempt_number
  FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'staging_call_logs',
    START_TIME => DATEADD(days, -7, CURRENT_TIMESTAMP())
  ))
)
SELECT 
  file_name,
  attempt_number,
  status,
  last_load_time,
  first_error_message
FROM numbered_attempts
WHERE file_name IN (
  SELECT file_name 
  FROM numbered_attempts 
  GROUP BY file_name 
  HAVING COUNT(*) > 1
)
ORDER BY file_name, attempt_number;

-- =====================================================
-- 5. CROSS-REFERENCE RETRIES VS LOAD SUCCESS
-- =====================================================

-- Check if retried files eventually succeeded
SELECT 
  f.file_name,
  f.retry_count as n8n_retry_count,
  f.failure_time as first_failure_time,
  c.status as final_status,
  c.last_load_time as final_load_time,
  DATEDIFF('minute', f.failure_time, c.last_load_time) as resolution_time_minutes
FROM snowpipe_failure_logs f
LEFT JOIN TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -7, CURRENT_TIMESTAMP())
)) c
  ON UPPER(f.file_name) = UPPER(c.file_name)
  AND c.last_load_time > f.failure_time
  AND c.status = 'LOADED'
ORDER BY f.failure_time DESC;

-- =====================================================
-- 6. LOAD SUCCESS RATE
-- =====================================================

SELECT 
  DATE_TRUNC('day', last_load_time) as load_date,
  COUNT(*) as total_attempts,
  COUNT_IF(status = 'LOADED') as successful_loads,
  COUNT_IF(status = 'LOAD_FAILED') as failed_loads,
  COUNT_IF(status = 'PARTIALLY_LOADED') as partial_loads,
  SUM(row_count) as total_rows_loaded,
  SUM(error_count) as total_errors,
  ROUND(failed_loads / total_attempts * 100, 2) as failure_rate_pct
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -30, CURRENT_TIMESTAMP())
))
GROUP BY load_date
ORDER BY load_date DESC;

-- =====================================================
-- 7. CHECK PIPE STATUS
-- =====================================================

-- Real-time pipe status
SELECT SYSTEM$PIPE_STATUS('call_logs_pipe') as pipe_status;

-- Pipe details
SHOW PIPES LIKE 'call_logs_pipe';

-- =====================================================
-- 8. CHECK WAREHOUSE USAGE AND COSTS
-- =====================================================

-- Warehouse credit usage (last 7 days)
SELECT 
  DATE_TRUNC('day', start_time) as day,
  warehouse_name,
  SUM(credits_used) as total_credits,
  COUNT(*) as query_count,
  ROUND(SUM(credits_used) * 2, 2) as estimated_cost_usd
FROM snowflake.account_usage.warehouse_metering_history
WHERE warehouse_name = 'MONITOR_WH'
AND start_time > DATEADD(days, -7, CURRENT_TIMESTAMP())
GROUP BY day, warehouse_name
ORDER BY day DESC;

-- =====================================================
-- 9. CHECK RECENT QUERIES
-- =====================================================

-- Recent queries on staging table
SELECT 
  query_text,
  user_name,
  warehouse_name,
  execution_time,
  start_time,
  credits_used_cloud_services
FROM snowflake.account_usage.query_history
WHERE query_text ILIKE '%staging_call_logs%'
AND start_time > DATEADD(days, -1, CURRENT_TIMESTAMP())
ORDER BY start_time DESC
LIMIT 20;

-- =====================================================
-- 10. DATA VOLUME CHECK
-- =====================================================

-- Total rows in staging table
SELECT COUNT(*) as total_rows FROM staging_call_logs;

-- Rows loaded per day
SELECT 
  DATE_TRUNC('day', last_load_time) as load_date,
  COUNT(DISTINCT file_name) as files_loaded,
  SUM(row_count) as rows_loaded
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -30, CURRENT_TIMESTAMP())
))
WHERE status = 'LOADED'
GROUP BY load_date
ORDER BY load_date DESC;

-- =====================================================
-- 11. ERROR SUMMARY
-- =====================================================

-- Most common error messages
SELECT 
  SUBSTRING(first_error_message, 1, 100) as error_summary,
  COUNT(*) as error_count,
  COUNT(DISTINCT file_name) as affected_files
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -30, CURRENT_TIMESTAMP())
))
WHERE status = 'LOAD_FAILED'
GROUP BY error_summary
ORDER BY error_count DESC
LIMIT 10;

-- =====================================================
-- 12. FILES PENDING RETRY
-- =====================================================

-- Files that failed but haven't reached max retries
SELECT 
  f.file_name,
  f.retry_count,
  f.error_message,
  f.failure_time,
  CASE 
    WHEN f.retry_count < 3 THEN 'Will auto-retry'
    WHEN f.retry_count >= 3 AND f.notified = FALSE THEN 'Needs manual intervention'
    ELSE 'Resolved or notified'
  END as status
FROM snowpipe_failure_logs f
WHERE failure_time > DATEADD(days, -7, CURRENT_TIMESTAMP())
ORDER BY retry_count DESC, failure_time DESC;
