# Troubleshooting Guide

Common issues and solutions for the Snowpipe Auto-Retry & Alerting System.

---

## Table of Contents

1. Snowflake Issues
2. AWS/S3 Issues
3. n8n Workflow Issues
4. Slack Notification Issues
5. Performance Issues
6. Data Quality Issues

---

## Snowflake Issues

### Issue: Snowpipe Not Ingesting Files

**Symptoms:**
- Files uploaded to S3 but not appearing in Snowflake
- No entries in COPY_HISTORY

**Diagnosis:**
```sql
-- Check pipe status
SELECT SYSTEM$PIPE_STATUS('call_logs_pipe');

-- Check pipe definition
SHOW PIPES LIKE 'call_logs_pipe';

-- Verify storage integration
SHOW INTEGRATIONS;
DESC INTEGRATION s3_integration;
```

**Solutions:**

1. **Verify pipe is running:**
```sql
-- Resume pipe if paused
ALTER PIPE call_logs_pipe SET PIPE_EXECUTION_PAUSED = FALSE;
```

2. **Check SNS subscription:**
```sql
-- Get SNS topic from pipe
SHOW PIPES LIKE 'call_logs_pipe';
-- Verify the notification_channel matches your SNS topic ARN
```

3. **Verify IAM permissions:**
- S3 bucket policy allows Snowflake role
- SNS topic policy allows Snowflake to subscribe
- Storage integration has correct external ID

4. **Check S3 event notifications:**
- Go to S3 bucket → Properties → Event notifications
- Verify notification is active and points to correct SNS topic
- Test by uploading a file

**Common Causes:**
- Pipe paused manually
- SNS subscription not confirmed
- S3 event notification misconfigured
- IAM role trust relationship broken

---

### Issue: COPY_HISTORY Shows No Failures

**Symptoms:**
- n8n workflow returns empty results
- No failed loads visible

**Diagnosis:**
```sql
-- Check all load history (not just failures)
SELECT 
  file_name,
  status,
  last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -7, CURRENT_TIMESTAMP())
))
ORDER BY last_load_time DESC
LIMIT 100;

-- Check if ANY files were loaded
SELECT COUNT(*) as total_loads
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -7, CURRENT_TIMESTAMP())
));
```

**Solutions:**

1. **If count = 0:** No files loaded at all → Check Snowpipe ingestion (see above)

2. **If count > 0 but no failures:** Good! Your data quality is excellent. Test with a bad file:
```bash
# Upload a file with intentional errors
aws s3 cp test-data/call_logs_bad_schema.csv s3://your-bucket/inbound/
```

3. **Check time window:**
```sql
-- Extend time window
START_TIME => DATEADD(days, -30, CURRENT_TIMESTAMP())  -- Look back 30 days
```

---

### Issue: "Table Does Not Exist" Error

**Symptoms:**
- n8n workflow fails with "Table 'STAGING_CALL_LOGS' does not exist"

**Diagnosis:**
```sql
-- Verify table exists
SHOW TABLES LIKE '%CALL_LOGS%';

-- Check current context
SELECT CURRENT_DATABASE(), CURRENT_SCHEMA();

-- Check table with full path
SELECT COUNT(*) FROM snowpipe_monitor_demo.raw.staging_call_logs;
```

**Solutions:**

1. **Add explicit context to queries:**
```sql
USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

SELECT * FROM staging_call_logs;
```

2. **Use fully qualified table names:**
```sql
SELECT * FROM snowpipe_monitor_demo.raw.staging_call_logs;
```

3. **Verify n8n credential has default database/schema set:**
- n8n → Credentials → Snowflake
- Set Database: `snowpipe_monitor_demo`
- Set Schema: `raw`
- Set Warehouse: `monitor_wh`

---

### Issue: Permission Denied Errors

**Symptoms:**
- "Insufficient privileges to operate on pipe"
- "SQL access control error"

**Diagnosis:**
```sql
-- Check current role
SELECT CURRENT_ROLE();

-- Check grants on pipe
SHOW GRANTS ON PIPE call_logs_pipe;

-- Check grants to user
SHOW GRANTS TO USER n8n_monitor;
```

**Solutions:**

1. **Grant required permissions:**
```sql
-- As ACCOUNTADMIN
USE ROLE ACCOUNTADMIN;

GRANT USAGE ON DATABASE snowpipe_monitor_demo TO USER n8n_monitor;
GRANT USAGE ON SCHEMA snowpipe_monitor_demo.raw TO USER n8n_monitor;
GRANT USAGE ON WAREHOUSE monitor_wh TO USER n8n_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA snowpipe_monitor_demo.raw TO USER n8n_monitor;
GRANT INSERT, UPDATE ON TABLE snowpipe_monitor_demo.raw.snowpipe_failure_logs TO USER n8n_monitor;
GRANT OPERATE ON PIPE snowpipe_monitor_demo.raw.call_logs_pipe TO USER n8n_monitor;
GRANT IMPORTED PRIVILEGES ON DATABASE snowflake TO USER n8n_monitor;
```

2. **Verify COPY_HISTORY access:**
```sql
-- Test as n8n_monitor user
SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(days, -1, CURRENT_TIMESTAMP())
))
LIMIT 1;
```

---

## AWS/S3 Issues

### Issue: Files Not Triggering SNS Events

**Symptoms:**
- Files uploaded to S3 but Snowpipe doesn't detect them
- No messages in SNS topic

**Diagnosis:**
```bash
# Check S3 event notification configuration
aws s3api get-bucket-notification-configuration \
  --bucket your-bucket-name

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:region:account:snowpipe-s3-events
```

**Solutions:**

1. **Verify S3 event notification:**
```json
{
  "TopicConfigurations": [
    {
      "Id": "snowpipe-notification",
      "TopicArn": "arn:aws:sns:ap-southeast-1:YOUR_ACCOUNT:snowpipe-s3-events",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "inbound/"
            }
          ]
        }
      }
    }
  ]
}
```

2. **Test SNS manually:**
```bash
# Publish test message
aws sns publish \
  --topic-arn arn:aws:sns:region:account:snowpipe-s3-events \
  --message "Test message"
```

3. **Check SNS topic policy allows S3:**
```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "arn:aws:sns:region:account:snowpipe-s3-events",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "arn:aws:s3:::your-bucket-name"
        }
      }
    }
  ]
}
```

---

### Issue: Snowflake Can't Access S3

**Symptoms:**
- "Access Denied" errors in COPY_HISTORY
- Files visible in S3 but Snowpipe fails to read

**Diagnosis:**
```sql
-- Test stage access
LIST @s3_external_stage;

-- Try manual COPY
COPY INTO staging_call_logs
FROM @s3_external_stage/call_logs_good_001.csv
FILE_FORMAT = strict_csv
VALIDATION_MODE = 'RETURN_ERRORS';
```

**Solutions:**

1. **Verify IAM role trust relationship:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::SNOWFLAKE_ACCOUNT:user/snowflake-s3-user"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "SNOWFLAKE_EXTERNAL_ID"
        }
      }
    }
  ]
}
```

2. **Check S3 bucket policy:**
```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::YOUR_ACCOUNT:role/snowflake-s3-access-role"
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    }
  ]
}
```

3. **Recreate storage integration:**
```sql
-- Drop and recreate
DROP STORAGE INTEGRATION s3_integration;

CREATE STORAGE INTEGRATION s3_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = S3
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::YOUR_ACCOUNT:role/snowflake-s3-access-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://your-bucket-name/inbound/');

-- Get new IAM details
DESC STORAGE INTEGRATION s3_integration;
-- Update IAM trust relationship with new STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID
```

---

## n8n Workflow Issues

### Issue: "No Fields - Item Exists But Empty"

**Symptoms:**
- Process Failures node shows empty output
- Missing `file_name`, `error_message` fields

**Diagnosis:**
- Check "Query Failed Loads" output
- Check "Get Retry Count" output
- Review node connections

**Solutions:**

1. **Verify node connections:**
```
Query Failed Loads → IF - Failures Exist? → Get Retry Count → Process Failures
```

2. **Check "Always Output Data" setting:**
- Click each Snowflake node
- Settings tab → "Always Output Data" = ON

3. **Test explicit node references:**
```javascript
// In Process Failures node
const failures = $('Query Failed Loads').all();
console.log('Failures:', JSON.stringify(failures));

const retryCounts = $('Get Retry Count').all();
console.log('Retry counts:', JSON.stringify(retryCounts));
```

4. **Check browser console for errors:**
- F12 → Console tab
- Look for JavaScript errors

---

### Issue: Case Sensitivity Errors

**Symptoms:**
- `file_name` is undefined
- Retry count always 0 even after retries

**Diagnosis:**
```javascript
// Check what column names are returned
console.log('Keys:', Object.keys(failures[0]?.json || {}));
```

**Solutions:**

1. **Handle both cases in code:**
```javascript
const fileName = (failure.json.FILE_NAME || failure.json.file_name || '').toUpperCase();
const pipeName = (failure.json.PIPE_NAME || failure.json.pipe_name || 'MANUAL_LOAD').toUpperCase();
```

2. **Normalize in SQL queries:**
```sql
SELECT 
  UPPER(file_name) as FILE_NAME,
  UPPER(pipe_name) as PIPE_NAME,
  -- other columns
FROM ...
```

---

### Issue: SQL Injection Error in Log Retry

**Symptoms:**
- "SQL compilation error: unclosed string"
- Error occurs when logging retry attempt

**Diagnosis:**
- Check if error_message contains single quotes
- Review INSERT statement

**Solutions:**

1. **Escape single quotes:**
```sql
INSERT INTO snowpipe_failure_logs 
(pipe_name, file_name, retry_count, error_message)
VALUES (
  '{{ $("Process Failures").item.json.pipe_name }}',
  '{{ $("Process Failures").item.json.file_name }}',
  {{ $("Process Failures").item.json.retry_count + 1 }},
  '{{ $("Process Failures").item.json.error_message.replace(/'/g, "''") }}'
);
```

2. **Truncate long error messages:**
```javascript
error_message: errorMessage.substring(0, 200)  // Limit to 200 chars
```

---

### Issue: Workflow Not Executing on Schedule

**Symptoms:**
- Manual execution works
- Schedule trigger doesn't fire

**Diagnosis:**
- Check workflow is ACTIVE (toggle in top right)
- Check n8n logs for errors

**Solutions:**

1. **Activate workflow:**
- Top right toggle: OFF → ON

2. **Check Schedule Trigger configuration:**
- Trigger node → Parameters
- Verify cron expression or interval

3. **Check n8n instance is running:**
```bash
# If self-hosted
docker ps | grep n8n

# Check logs
docker logs n8n
```

4. **Railway-specific:**
- Go to Railway dashboard
- Check service is deployed and running
- View logs for errors

---

## Slack Notification Issues

### Issue: No Slack Notifications Received

**Symptoms:**
- Workflow executes successfully
- No messages in Slack channel

**Diagnosis:**
- Check HTTP Request node output
- Test webhook URL manually

**Solutions:**

1. **Test webhook manually:**
```bash
curl -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test message from troubleshooting"}'
```

2. **Verify webhook URL is correct:**
- Slack App → Incoming Webhooks
- Copy exact URL (includes /services/...)

3. **Check HTTP Request node configuration:**
- Method: POST
- URL: Your webhook URL
- Body Content Type: JSON
- JSON Body: Valid JSON

4. **Check for rate limiting:**
- Slack webhooks: 1 message per second
- If sending multiple alerts, add delay between them

---

### Issue: Slack Message Formatting Issues

**Symptoms:**
- Messages appear but formatting is broken
- Variables not replaced

**Diagnosis:**
- Check if JSON is valid
- Check variable references

**Solutions:**

1. **Validate JSON:**
```json
{
  "text": "Snowpipe Auto-Retry notification with pipe and file details"
}
```

2. **Escape special characters:**
- Use `\n` for newlines
- Use `\"` for quotes inside strings

3. **Use proper node references:**
```javascript
// Correct
{{ $('Process Failures').item.json.file_name }}

// Incorrect
{{ $input.json.file_name }}  // May be empty depending on flow
```

---

## Performance Issues

### Issue: High Snowflake Costs

**Symptoms:**
- Warehouse costs higher than expected
- Credits consumed rapidly

**Diagnosis:**
```sql
-- Check warehouse usage
SELECT 
  warehouse_name,
  SUM(credits_used) as total_credits,
  COUNT(*) as query_count
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time > DATEADD(days, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY total_credits DESC;

-- Check query history
SELECT 
  query_text,
  execution_time,
  warehouse_name,
  credits_used_cloud_services
FROM snowflake.account_usage.query_history
WHERE warehouse_name = 'MONITOR_WH'
AND start_time > DATEADD(days, -1, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;
```

**Solutions:**

1. **Reduce n8n execution frequency:**
```
5 minutes → 15 minutes (saves ~66% warehouse cost)
5 minutes → 30 minutes (saves ~83% warehouse cost)
```

2. **Reduce warehouse auto-suspend time:**
```sql
ALTER WAREHOUSE monitor_wh SET AUTO_SUSPEND = 60;  -- 1 minute
```

3. **Optimize queries:**
```sql
-- Add time filter to reduce data scanned
WHERE last_load_time > DATEADD(hours, -1, CURRENT_TIMESTAMP())
-- Instead of
WHERE last_load_time > DATEADD(days, -7, CURRENT_TIMESTAMP())
```

---

### Issue: n8n Workflow Takes Too Long

**Symptoms:**
- Workflow execution >30 seconds
- Timeouts

**Diagnosis:**
- Check execution time in n8n
- Check Snowflake query performance

**Solutions:**

1. **Optimize Snowflake queries:**
```sql
-- Add LIMIT to queries
SELECT ... 
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(...))
WHERE status = 'LOAD_FAILED'
ORDER BY last_load_time DESC
LIMIT 100;  -- Only get recent failures
```

2. **Reduce time window:**
```sql
START_TIME => DATEADD(hours, -2, CURRENT_TIMESTAMP())  -- 2 hours instead of 24
```

3. **Use smaller warehouse:**
- X-Small is sufficient for monitoring queries
- Don't use Medium/Large for simple SELECTs

---

## Data Quality Issues

### Issue: Same File Keeps Failing

**Symptoms:**
- File retried 3 times, all failures
- Same error message each time

**Diagnosis:**
```sql
-- Check failure pattern
SELECT 
  file_name,
  retry_count,
  error_message,
  failure_time
FROM snowpipe_failure_logs
WHERE file_name = 'problematic_file.csv'
ORDER BY failure_time;

-- Check actual error from COPY_HISTORY
SELECT first_error_message, first_error_line_number
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(...))
WHERE file_name = 'problematic_file.csv'
AND status = 'LOAD_FAILED';
```

**Solutions:**

1. **Schema mismatch:**
```sql
-- Fix: Update file format or fix source file
-- Check column count
SELECT COUNT(*) as column_count 
FROM TABLE(INFER_SCHEMA(
  LOCATION => '@s3_external_stage/problematic_file.csv',
  FILE_FORMAT => 'strict_csv'
));
```

2. **Data type errors:**
- Download file and inspect the failing row
- Fix source data
- Re-upload with new filename

3. **NULL violations:**
```sql
-- Temporary fix: Make column nullable
ALTER TABLE staging_call_logs ALTER COLUMN call_rating DROP NOT NULL;
```

4. **Move to quarantine:**
```bash
# Move bad file out of inbound/
aws s3 mv s3://bucket/inbound/bad_file.csv s3://bucket/failed/bad_file.csv
```

---

### Issue: Snowpipe Not Re-Processing Fixed Files

**Symptoms:**
- Fixed file uploaded with same name
- Snowpipe doesn't reload it

**Diagnosis:**
- Snowpipe tracks file metadata (name + size + timestamp)
- Won't reload identical metadata

**Solutions:**

1. **Use different filename:**
```bash
# Instead of: data.csv
# Use: data_v2.csv or data_20260420.csv
```

2. **Force reload with COPY INTO:**
```sql
COPY INTO staging_call_logs
FROM @s3_external_stage/data.csv
FILE_FORMAT = strict_csv
FORCE = TRUE;  -- Bypasses metadata check
```

3. **Clear pipe metadata (use with caution):**
```sql
-- This resets the pipe's file tracking
ALTER PIPE call_logs_pipe REFRESH;
```

---

## Getting Help

### Before Opening an Issue

1. **Check logs:**
   - n8n execution logs
   - Snowflake query history
   - AWS CloudTrail (for S3/SNS events)

2. **Test components individually:**
   - Upload file → Check S3
   - Check SNS topic → Check subscriptions
   - Test Snowpipe manually → `ALTER PIPE REFRESH`
   - Run n8n nodes one-by-one

3. **Collect diagnostic info:**
```sql
-- Snowflake version
SELECT CURRENT_VERSION();

-- Pipe status
SELECT SYSTEM$PIPE_STATUS('call_logs_pipe');

-- Recent load history
SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
))
ORDER BY last_load_time DESC
LIMIT 10;
```

### Support Channels

- GitHub Issues: Create an issue in your repository
- n8n Community: community.n8n.io
- Snowflake Support: community.snowflake.com

---

## Common Error Messages Reference

| Error | Cause | Solution |
|-------|-------|----------|
| `Insufficient privileges to operate on pipe` | Missing OPERATE grant | `GRANT OPERATE ON PIPE ... TO USER` |
| `Table does not exist` | Wrong database/schema context | Add `USE DATABASE/SCHEMA` to query |
| `Access Denied` (S3) | IAM permissions issue | Verify bucket policy and role trust |
| `Invalid SNS topic ARN` | Wrong SNS ARN in pipe | Check SNS topic ARN format |
| `SQL compilation error: unclosed string` | Unescaped quotes in data | Use `.replace(/'/g, "''")` |
| `Object does not exist` (stage) | Storage integration issue | Recreate storage integration |
| `Copy executed with 0 files processed` | File already loaded or no matching files | Check file metadata, try new filename |

---

Last Updated: 2026-04-20  
Version: 1.0.0
