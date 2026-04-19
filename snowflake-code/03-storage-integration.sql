-- =====================================================
-- Snowpipe Auto-Retry System - Storage Integration
-- =====================================================

USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

-- =====================================================
-- 1. CREATE STORAGE INTEGRATION
-- =====================================================
-- NOTE: Replace YOUR_ACCOUNT_ID and YOUR_BUCKET_NAME with actual values

CREATE STORAGE INTEGRATION IF NOT EXISTS s3_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = S3
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::YOUR_ACCOUNT_ID:role/snowflake-s3-access-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://YOUR_BUCKET_NAME/inbound/')
  COMMENT = 'Integration for S3 bucket access';

-- =====================================================
-- 2. GET IAM USER DETAILS FOR AWS SETUP
-- =====================================================
-- IMPORTANT: Run this and copy the output values
-- You need these to update the IAM role trust policy in AWS

DESC STORAGE INTEGRATION s3_integration;

/*
COPY THESE VALUES FROM OUTPUT:
- STORAGE_AWS_IAM_USER_ARN
- STORAGE_AWS_EXTERNAL_ID

Then update IAM role trust policy in AWS Console:
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "<STORAGE_AWS_IAM_USER_ARN>"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "<STORAGE_AWS_EXTERNAL_ID>"
        }
      }
    }
  ]
}
*/

-- =====================================================
-- 3. CREATE EXTERNAL STAGE
-- =====================================================
-- NOTE: Replace YOUR_BUCKET_NAME with actual value

CREATE STAGE IF NOT EXISTS s3_external_stage
  STORAGE_INTEGRATION = s3_integration
  URL = 's3://YOUR_BUCKET_NAME/inbound/'
  FILE_FORMAT = strict_csv
  COMMENT = 'External stage pointing to S3 inbound folder';

-- =====================================================
-- 4. TEST STAGE ACCESS
-- =====================================================

-- List files in stage (should be empty initially)
LIST @s3_external_stage;

-- =====================================================
-- 5. VERIFY SETUP
-- =====================================================

SHOW INTEGRATIONS;
SHOW STAGES IN SCHEMA snowpipe_monitor_demo.raw;
