-- =====================================================
-- Snowpipe Auto-Retry System - Snowpipe Setup
-- =====================================================


USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

-- =====================================================
-- 1. GET SNS TOPIC POLICY
-- =====================================================
-- NOTE: Replace with your actual SNS topic ARN

-- Get the SNS policy that needs to be added to your AWS SNS topic
SELECT SYSTEM$GET_AWS_SNS_IAM_POLICY('arn:aws:sns:ap-southeast-1:YOUR_ACCOUNT_ID:snowpipe-s3-events');

/*
IMPORTANT: Copy the output from above query and add it to your SNS topic access policy in AWS

Steps:
1. Go to AWS SNS Console
2. Select your topic: snowpipe-s3-events
3. Click "Edit"
4. Under "Access policy", add the statement returned by the query above
5. Save changes
*/

-- =====================================================
-- 2. CREATE SNOWPIPE
-- =====================================================
-- NOTE: Replace YOUR_ACCOUNT_ID with actual value

CREATE PIPE IF NOT EXISTS call_logs_pipe
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = 'arn:aws:sns:ap-southeast-1:YOUR_ACCOUNT_ID:snowpipe-s3-events'
  COMMENT = 'Auto-ingest pipe for call logs from S3'
AS
  COPY INTO staging_call_logs
  FROM @s3_external_stage
  FILE_FORMAT = strict_csv;

-- =====================================================
-- 3. CHECK PIPE STATUS
-- =====================================================

-- View pipe status
SELECT SYSTEM$PIPE_STATUS('call_logs_pipe');

-- Show pipe details
SHOW PIPES LIKE 'call_logs_pipe';

-- =====================================================
-- 4. VERIFY SETUP
-- =====================================================

/*
AWS S3 EVENT NOTIFICATION SETUP:

1. Go to S3 Console
2. Select your bucket
3. Go to Properties tab
4. Scroll to "Event notifications"
5. Click "Create event notification"
6. Configure:
   - Name: snowpipe-notification
   - Event types: All object create events
   - Prefix: inbound/
   - Destination: SNS topic
   - SNS topic: snowpipe-s3-events
7. Save
*/
