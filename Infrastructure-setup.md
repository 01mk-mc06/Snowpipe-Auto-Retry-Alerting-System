# Infrastructure Setup Guide

Complete step-by-step guide to set up the Snowpipe Auto-Retry & Alerting System infrastructure.

---

## Table of Contents

1. Prerequisites
2. AWS Setup
3. Snowflake Setup
4. n8n Setup
5. Slack Setup
6. Integration Testing
7. Production Deployment

---

## Prerequisites

### Required Accounts
- [ ] AWS account with S3 and SNS access
- [ ] Snowflake account (Standard edition or higher)
- [ ] Railway account OR self-hosted server for n8n
- [ ] Slack workspace with admin permissions

### Required Tools
```bash
# AWS CLI
aws --version  # Should be 2.x

# SnowSQL (optional but recommended)
snowsql --version

# Git
git --version
```

### Required Permissions

**AWS:**
- Create S3 buckets
- Create SNS topics
- Create IAM roles and policies
- Configure S3 event notifications

**Snowflake:**
- ACCOUNTADMIN role (for initial setup)
- Create databases, schemas, warehouses
- Create storage integrations
- Create pipes

**Slack:**
- Install apps
- Create incoming webhooks

---

## AWS Setup

### Step 1: Create S3 Bucket

**Via AWS Console:**

1. Go to **S3** → **Create bucket**
2. Configure:
   - **Bucket name:** `snowpipe-monitor-demo-YOURNAME` (must be globally unique)
   - **Region:** `ap-southeast-1` (or your preferred region)
   - **Block Public Access:** Keep all enabled (default)
   - **Bucket Versioning:** Disabled (not required)
   - **Tags:** Add optional tags

3. Click **Create bucket**

**Via AWS CLI:**

```bash
# Set variables
export BUCKET_NAME="snowpipe-monitor-demo-$(date +%s)"
export AWS_REGION="ap-southeast-1"

# Create bucket
aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}

# Create folder structure
aws s3api put-object --bucket ${BUCKET_NAME} --key inbound/
aws s3api put-object --bucket ${BUCKET_NAME} --key processed/
aws s3api put-object --bucket ${BUCKET_NAME} --key failed/
```

---

### Step 2: Create SNS Topic

**Via AWS Console:**

1. Go to **SNS** → **Topics** → **Create topic**
2. Configure:
   - **Type:** Standard
   - **Name:** `snowpipe-s3-events`
   - **Display name:** `Snowpipe S3 Event Notifications`

3. Click **Create topic**
4. **Copy the Topic ARN** (you'll need this later)

**Via AWS CLI:**

```bash
# Create SNS topic
aws sns create-topic \
  --name snowpipe-s3-events \
  --region ${AWS_REGION}

# Output will include TopicArn - save this
export SNS_TOPIC_ARN="arn:aws:sns:ap-southeast-1:YOUR_ACCOUNT:snowpipe-s3-events"
```

---

### Step 3: Configure SNS Topic Policy

**Allow S3 to publish to SNS:**

1. Go to **SNS** → **Topics** → Select `snowpipe-s3-events`
2. Click **Edit**
3. Expand **Access policy**
4. Add this statement:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "arn:aws:sns:ap-southeast-1:YOUR_ACCOUNT_ID:snowpipe-s3-events",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "arn:aws:s3:::snowpipe-monitor-demo-YOURNAME"
        }
      }
    }
  ]
}
```

5. Click **Save changes**

**Via AWS CLI:**

```bash
# Create policy file
cat > sns-topic-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "${SNS_TOPIC_ARN}",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "arn:aws:s3:::${BUCKET_NAME}"
        }
      }
    }
  ]
}
EOF

# Apply policy
aws sns set-topic-attributes \
  --topic-arn ${SNS_TOPIC_ARN} \
  --attribute-name Policy \
  --attribute-value file://sns-topic-policy.json
```

---

### Step 4: Create IAM Role for Snowflake

**Via AWS Console:**

1. Go to **IAM** → **Roles** → **Create role**
2. **Trusted entity type:** Custom trust policy
3. Paste this trust policy (temporary - will update after Snowflake integration):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::YOUR_ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

4. Click **Next**
5. **Role name:** `snowflake-s3-access-role`
6. Click **Create role**

7. **Attach inline policy:**
   - Go to role → **Permissions** → **Add permissions** → **Create inline policy**
   - JSON editor:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::snowpipe-monitor-demo-YOURNAME",
        "arn:aws:s3:::snowpipe-monitor-demo-YOURNAME/*"
      ]
    }
  ]
}
```

8. **Policy name:** `snowflake-s3-read-policy`
9. Click **Create policy**

**Via AWS CLI:**

```bash
# Create trust policy file
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name snowflake-s3-access-role \
  --assume-role-policy-document file://trust-policy.json

# Create permission policy
cat > s3-read-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF

# Attach policy
aws iam put-role-policy \
  --role-name snowflake-s3-access-role \
  --policy-name snowflake-s3-read-policy \
  --policy-document file://s3-read-policy.json

# Get role ARN
export ROLE_ARN=$(aws iam get-role --role-name snowflake-s3-access-role --query 'Role.Arn' --output text)
echo "Role ARN: ${ROLE_ARN}"
```

---

## Snowflake Setup

### Step 1: Create Database and Schema

```sql
-- Switch to ACCOUNTADMIN
USE ROLE ACCOUNTADMIN;

-- Create database
CREATE DATABASE IF NOT EXISTS snowpipe_monitor_demo
  COMMENT = 'Snowpipe monitoring and auto-retry system';

USE DATABASE snowpipe_monitor_demo;

-- Create schema
CREATE SCHEMA IF NOT EXISTS raw
  COMMENT = 'Raw data landing zone';

USE SCHEMA raw;
```

---

### Step 2: Create Warehouse

```sql
-- Create monitoring warehouse
CREATE WAREHOUSE IF NOT EXISTS monitor_wh
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for n8n monitoring queries';

-- Grant usage to SYSADMIN
GRANT USAGE ON WAREHOUSE monitor_wh TO ROLE SYSADMIN;
```

---

### Step 3: Create Tables

```sql
USE WAREHOUSE monitor_wh;
USE DATABASE snowpipe_monitor_demo;
USE SCHEMA raw;

-- Staging table for incoming data
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
COMMENT = 'Staging table for BPO call center logs';

-- Retry tracking table
CREATE TABLE IF NOT EXISTS snowpipe_failure_logs (
  log_id NUMBER AUTOINCREMENT PRIMARY KEY,
  pipe_name VARCHAR(100),
  file_name VARCHAR(500),
  retry_count NUMBER,
  error_message VARCHAR(5000),
  failure_time TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  notified BOOLEAN DEFAULT FALSE
)
COMMENT = 'Tracks Snowpipe failure retry attempts';
```

---

### Step 4: Create File Format

```sql
-- Strict CSV file format
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
```

---

### Step 5: Create Storage Integration

```sql
-- Create storage integration
CREATE STORAGE INTEGRATION s3_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = S3
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::YOUR_ACCOUNT_ID:role/snowflake-s3-access-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://snowpipe-monitor-demo-YOURNAME/inbound/');

-- Describe integration to get IAM details
DESC STORAGE INTEGRATION s3_integration;
```

**IMPORTANT: Copy these values from the output:**
- `STORAGE_AWS_IAM_USER_ARN` 
- `STORAGE_AWS_EXTERNAL_ID`

You'll need these to update the IAM role trust policy in AWS.

---

### Step 6: Update IAM Role Trust Policy

**Go back to AWS Console:**

1. Go to **IAM** → **Roles** → `snowflake-s3-access-role`
2. **Trust relationships** → **Edit trust policy**
3. Replace with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "STORAGE_AWS_IAM_USER_ARN_FROM_SNOWFLAKE"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "STORAGE_AWS_EXTERNAL_ID_FROM_SNOWFLAKE"
        }
      }
    }
  ]
}
```

4. Click **Update policy**

**Via AWS CLI:**

```bash
# Update trust policy (replace with your values)
cat > updated-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "STORAGE_AWS_IAM_USER_ARN_FROM_SNOWFLAKE"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "STORAGE_AWS_EXTERNAL_ID_FROM_SNOWFLAKE"
        }
      }
    }
  ]
}
EOF

aws iam update-assume-role-policy \
  --role-name snowflake-s3-access-role \
  --policy-document file://updated-trust-policy.json
```

---

### Step 7: Create External Stage

```sql
-- Create stage pointing to S3
CREATE STAGE IF NOT EXISTS s3_external_stage
  STORAGE_INTEGRATION = s3_integration
  URL = 's3://snowpipe-monitor-demo-YOURNAME/inbound/'
  FILE_FORMAT = strict_csv
  COMMENT = 'External stage for S3 inbound files';

-- Test stage access
LIST @s3_external_stage;
```

---

### Step 8: Create Snowpipe

**First, get SNS topic policy for Snowflake:**

```sql
-- Get SNS policy
SELECT SYSTEM$GET_AWS_SNS_IAM_POLICY('arn:aws:sns:ap-southeast-1:YOUR_ACCOUNT:snowpipe-s3-events');
```

**Copy the output and add it to SNS topic access policy in AWS:**

1. Go to **SNS** → **Topics** → `snowpipe-s3-events`
2. **Access policy** → Add the statement returned by Snowflake

**Then create the pipe:**

```sql
-- Create Snowpipe with auto-ingest
CREATE PIPE IF NOT EXISTS call_logs_pipe
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = 'arn:aws:sns:ap-southeast-1:YOUR_ACCOUNT:snowpipe-s3-events'
  COMMENT = 'Auto-ingest pipe for call logs from S3'
AS
  COPY INTO staging_call_logs
  FROM @s3_external_stage
  FILE_FORMAT = strict_csv;

-- Check pipe status
SELECT SYSTEM$PIPE_STATUS('call_logs_pipe');

-- Show pipe details
SHOW PIPES LIKE 'call_logs_pipe';
```

---

### Step 9: Configure S3 Event Notifications

**Via AWS Console:**

1. Go to **S3** → Your bucket → **Properties**
2. Scroll to **Event notifications** → **Create event notification**
3. Configure:
   - **Name:** `snowpipe-notification`
   - **Event types:** Check `All object create events`
   - **Prefix:** `inbound/`
   - **Destination:** SNS topic
   - **SNS topic:** `snowpipe-s3-events`

4. Click **Save changes**

**Via AWS CLI:**

```bash
# Create notification configuration
cat > s3-notification.json <<EOF
{
  "TopicConfigurations": [
    {
      "Id": "snowpipe-notification",
      "TopicArn": "${SNS_TOPIC_ARN}",
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
EOF

# Apply notification
aws s3api put-bucket-notification-configuration \
  --bucket ${BUCKET_NAME} \
  --notification-configuration file://s3-notification.json
```

---

### Step 10: Create n8n Monitoring User

```sql
-- Create user for n8n
CREATE USER IF NOT EXISTS n8n_monitor
  PASSWORD = 'STRONG_PASSWORD_HERE'
  DEFAULT_WAREHOUSE = monitor_wh
  DEFAULT_NAMESPACE = snowpipe_monitor_demo.raw
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'Service account for n8n monitoring workflow';

-- Grant permissions
GRANT USAGE ON DATABASE snowpipe_monitor_demo TO USER n8n_monitor;
GRANT USAGE ON SCHEMA snowpipe_monitor_demo.raw TO USER n8n_monitor;
GRANT USAGE ON WAREHOUSE monitor_wh TO USER n8n_monitor;

-- Table permissions
GRANT SELECT ON ALL TABLES IN SCHEMA snowpipe_monitor_demo.raw TO USER n8n_monitor;
GRANT INSERT, UPDATE ON TABLE snowpipe_monitor_demo.raw.snowpipe_failure_logs TO USER n8n_monitor;

-- Stage and file format permissions
GRANT USAGE ON STAGE s3_external_stage TO USER n8n_monitor;
GRANT USAGE ON FILE FORMAT strict_csv TO USER n8n_monitor;
GRANT USAGE ON INTEGRATION s3_integration TO USER n8n_monitor;

-- Pipe permissions
GRANT OPERATE ON PIPE call_logs_pipe TO USER n8n_monitor;

-- COPY_HISTORY access
GRANT IMPORTED PRIVILEGES ON DATABASE snowflake TO USER n8n_monitor;

-- Test login
-- (Use SnowSQL or connector to test with n8n_monitor credentials)
```

---

## n8n Setup

### Option A: Railway Deployment (Recommended)

**Step 1: Create Railway Account**

1. Go to railway.app
2. Sign up with GitHub

**Step 2: Deploy n8n**

1. Click **New Project** → **Deploy from Template**
2. Search for "n8n"
3. Select **n8n** template
4. Click **Deploy**
5. Wait for deployment (~2-3 minutes)

**Step 3: Access n8n**

1. Go to **Deployments** → Click your n8n service
2. **Settings** → **Networking** → **Generate Domain**
3. Copy the URL (e.g., `your-app.railway.app`)
4. Open in browser
5. Create admin account

**Step 4: Configure Environment Variables**

1. **Settings** → **Variables**
2. Add:
   - `N8N_ENCRYPTION_KEY`: Generate random string
   - `WEBHOOK_URL`: Your Railway domain

---

### Option B: Self-Hosted with Docker

```bash
# Create directory
mkdir n8n-data
cd n8n-data

# Run n8n
docker run -d \
  --name n8n \
  -p 5678:5678 \
  -v $(pwd):/home/node/.n8n \
  -e N8N_BASIC_AUTH_ACTIVE=true \
  -e N8N_BASIC_AUTH_USER=admin \
  -e N8N_BASIC_AUTH_PASSWORD=your-password \
  n8nio/n8n

# Access at http://localhost:5678
```

---

### Step 5: Configure Snowflake Credential in n8n

1. In n8n, click **Settings** (gear icon) → **Credentials**
2. Click **Add Credential** → Search "Snowflake"
3. Configure:
   - **Account:** `YOUR_ACCOUNT.REGION` (e.g., `abc123.ap-southeast-1`)
   - **Username:** `n8n_monitor`
   - **Password:** (password you set earlier)
   - **Database:** `snowpipe_monitor_demo`
   - **Schema:** `raw`
   - **Warehouse:** `monitor_wh`
   - **Role:** `PUBLIC` (or custom role if created)

4. Click **Test** → Should show "Connection successful"
5. Click **Save**

---

### Step 6: Import Workflow

1. Download `Snowpipe_Failure_Monitor_TEMPLATE.json` from repository
2. In n8n, click **Import from File**
3. Select the JSON file
4. Click **Import**

---

### Step 7: Update Workflow Credentials

1. Click each **Snowflake** node
2. **Credentials** → Select the Snowflake credential you created
3. Click each **HTTP Request** node (Slack notifications)
4. Update **URL** with your Slack webhook (see Slack Setup below)

---

## Slack Setup

### Step 1: Create Slack App

1. Go to api.slack.com/apps
2. Click Create New App, then From scratch
3. Configure:
   - App Name: Snowpipe Monitor
   - Workspace: Select your workspace

4. Click Create App

---

### Step 2: Enable Incoming Webhooks

1. In app settings, click **Incoming Webhooks**
2. Toggle **Activate Incoming Webhooks** to ON
3. Click **Add New Webhook to Workspace**
4. Select channel (e.g., `#data-alerts`)
5. Click **Allow**

---

### Step 3: Copy Webhook URL

1. Copy the **Webhook URL** 
   - Format: `https://hooks.slack.com/services/T.../B.../...`
2. **SAVE THIS** - you'll use it in n8n

---

### Step 4: Test Webhook

```bash
# Test webhook
curl -X POST YOUR_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Snowpipe Monitor connected successfully!"}'
```

You should see the message in your Slack channel.

---

## Integration Testing

### Test 1: Upload Good File

```bash
# Create test data
cat > call_logs_good_001.csv <<EOF
call_id,agent_id,customer_phone,call_start_time,call_duration_seconds,call_outcome,call_rating,notes
1,AGT001,+1234567890,2026-04-20 10:00:00,180,Resolved,5,Customer satisfied
2,AGT002,+1234567891,2026-04-20 10:05:00,240,Escalated,3,Transferred to supervisor
3,AGT001,+1234567892,2026-04-20 10:10:00,90,Resolved,4,Quick resolution
EOF

# Upload to S3
aws s3 cp call_logs_good_001.csv s3://${BUCKET_NAME}/inbound/
```

**Expected:**
- Snowpipe loads file within 1-2 minutes
- Data appears in `staging_call_logs`
- No alerts (successful load)

**Verify:**
```sql
SELECT COUNT(*) FROM staging_call_logs;
-- Should return 3

SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(minutes, -10, CURRENT_TIMESTAMP())
));
-- Should show status = 'LOADED'
```

---

### Test 2: Upload Bad File (Trigger Failure)

```bash
# Create file with schema mismatch (7 columns instead of 8)
cat > call_logs_bad_schema.csv <<EOF
call_id,agent_id,customer_phone,call_start_time,call_duration_seconds,call_outcome,call_rating
4,AGT003,+1234567893,2026-04-20 11:00:00,150,Resolved,5
EOF

# Upload
aws s3 cp call_logs_bad_schema.csv s3://${BUCKET_NAME}/inbound/
```

**Expected:**
- Snowpipe fails to load
- COPY_HISTORY shows `LOAD_FAILED`

**Verify:**
```sql
SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(minutes, -10, CURRENT_TIMESTAMP())
))
WHERE status = 'LOAD_FAILED';
-- Should show the failed file
```

---

### Test 3: Run n8n Workflow

1. In n8n, open the Snowpipe monitor workflow
2. Click **Execute Workflow** (top right)
3. Check execution:
   - "Query Failed Loads" → Should show failed file
   - "Process Failures" → Should output file details
   - "Refresh Pipe" → Executes
   - "Log Retry Attempt" → Inserts row
   - "Slack Notification" → Sends alert

**Verify in Slack:**
- Should receive "Auto-Retry #1" notification

**Verify in Snowflake:**
```sql
SELECT * FROM snowpipe_failure_logs ORDER BY failure_time DESC;
-- Should show 1 row with retry_count = 1
```

---

### Test 4: Retry Exhaustion

```sql
-- Force retry count to 3
UPDATE snowpipe_failure_logs
SET retry_count = 3
WHERE file_name = 'call_logs_bad_schema.csv';
```

**Run workflow again:**
- Should send **critical alert** to Slack
- Should NOT refresh pipe

---

## Production Deployment

### Step 1: Change to Schedule Trigger

1. In n8n workflow, **delete** "When clicking 'Execute workflow'" node
2. Add **Schedule Trigger** node
3. Configure:
   - **Trigger Interval:** Every 5 minutes
   - OR **Cron Expression:** `*/5 * * * *`

4. Connect to "Query Failed Loads"

---

### Step 2: Activate Workflow

1. Toggle workflow to **Active** (top right)
2. Workflow will now run automatically

---

### Step 3: Monitor Performance

**Check Snowflake costs:**
```sql
SELECT 
  DATE_TRUNC('day', start_time) as day,
  warehouse_name,
  SUM(credits_used) as total_credits,
  COUNT(*) as query_count
FROM snowflake.account_usage.warehouse_metering_history
WHERE warehouse_name = 'MONITOR_WH'
AND start_time > DATEADD(days, -7, CURRENT_TIMESTAMP())
GROUP BY day, warehouse_name
ORDER BY day DESC;
```

**Check workflow execution history:**
- n8n → Executions tab
- Look for failures or long execution times

---

### Step 4: Set Up Monitoring Alerts

**Create Snowflake resource monitor:**
```sql
CREATE RESOURCE MONITOR monitor_limit
  WITH CREDIT_QUOTA = 10  -- $20/month at $2/credit
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE monitor_wh SET RESOURCE_MONITOR = monitor_limit;
```

---

## Configuration Files

Save these for reference:

**`.env.example`:**
```bash
# Snowflake
SNOWFLAKE_ACCOUNT=abc123.ap-southeast-1
SNOWFLAKE_USER=n8n_monitor
SNOWFLAKE_PASSWORD=your-password
SNOWFLAKE_WAREHOUSE=monitor_wh
SNOWFLAKE_DATABASE=snowpipe_monitor_demo
SNOWFLAKE_SCHEMA=raw

# AWS
AWS_ACCOUNT_ID=123456789012
AWS_REGION=ap-southeast-1
S3_BUCKET=snowpipe-monitor-demo-yourname
SNS_TOPIC_ARN=arn:aws:sns:region:account:topic

# Slack
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# n8n
N8N_WEBHOOK_URL=https://your-app.railway.app
```

---

## Next Steps

1. Test with more failure scenarios
2. Document your specific configuration
3. Set up monitoring dashboards
4. Create runbook for common issues
5. Train team on alert responses

---

Setup Complete!

Your Snowpipe auto-retry system is now operational.

**Support:**
- Troubleshooting: See TROUBLESHOOTING.md
- GitHub Issues: Create an issue in your repository

---

Last Updated: 2026-04-20  
Version: 1.0.0
