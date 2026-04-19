-- =====================================================
-- Snowpipe Auto-Retry System - Database Setup
-- =====================================================
-- Description: Creates database, schema, and warehouse

-- Switch to ACCOUNTADMIN role
USE ROLE ACCOUNTADMIN;

-- =====================================================
-- 1. CREATE DATABASE
-- =====================================================

CREATE DATABASE IF NOT EXISTS snowpipe_monitor_demo
  COMMENT = 'Snowpipe monitoring and auto-retry system';

USE DATABASE snowpipe_monitor_demo;

-- =====================================================
-- 2. CREATE SCHEMA
-- =====================================================

CREATE SCHEMA IF NOT EXISTS raw
  COMMENT = 'Raw data landing zone for Snowpipe ingestion';

USE SCHEMA raw;

-- =====================================================
-- 3. CREATE WAREHOUSE
-- =====================================================

CREATE WAREHOUSE IF NOT EXISTS monitor_wh
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for n8n monitoring queries and pipe operations';

-- Grant usage to SYSADMIN for future management
GRANT USAGE ON WAREHOUSE monitor_wh TO ROLE SYSADMIN;

-- =====================================================
-- 4. VERIFY SETUP
-- =====================================================

-- Show created objects
SHOW DATABASES LIKE 'snowpipe_monitor_demo';
SHOW SCHEMAS IN DATABASE snowpipe_monitor_demo;
SHOW WAREHOUSES LIKE 'monitor_wh';

-- Set context for next scripts
USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

