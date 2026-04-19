-- =====================================================
-- Snowpipe Auto-Retry System - Table Setup
-- =====================================================


USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

-- =====================================================
-- 1. CREATE STAGING TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS staging_call_logs (
  call_id NUMBER NOT NULL,
  agent_id VARCHAR(50) NOT NULL,
  customer_phone VARCHAR(20) NOT NULL,
  call_start_time TIMESTAMP_NTZ NOT NULL,
  call_duration_seconds NUMBER,
  call_outcome VARCHAR(50),
  call_rating NUMBER(1,0),
  notes VARCHAR(1000)
)
COMMENT = 'Staging table for BPO call center logs from Snowpipe';

-- =====================================================
-- 2. CREATE RETRY TRACKING TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS snowpipe_failure_logs (
  log_id NUMBER AUTOINCREMENT PRIMARY KEY,
  pipe_name VARCHAR(100),
  file_name VARCHAR(500),
  retry_count NUMBER,
  error_message VARCHAR(5000),
  failure_time TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  notified BOOLEAN DEFAULT FALSE
)
COMMENT = 'Tracks Snowpipe failure retry attempts and notification status';

-- =====================================================
-- 3. CREATE FILE FORMAT
-- =====================================================

CREATE FILE FORMAT IF NOT EXISTS strict_csv
  TYPE = 'CSV'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
  ESCAPE = 'NONE'
  ESCAPE_UNENCLOSED_FIELD = 'NONE'
  DATE_FORMAT = 'AUTO'
  TIMESTAMP_FORMAT = 'AUTO'
  NULL_IF = ('NULL', 'null', '')
  COMMENT = 'Strict CSV format for data quality enforcement';

-- =====================================================
-- 4. VERIFY SETUP
-- =====================================================

-- Show created objects
SHOW TABLES IN SCHEMA snowpipe_monitor_demo.raw;
SHOW FILE FORMATS IN SCHEMA snowpipe_monitor_demo.raw;

-- Describe table structures
DESC TABLE staging_call_logs;
DESC TABLE snowpipe_failure_logs;

SELECT 'Table setup completed successfully' AS status;
