# Snowpipe Auto-Retry & Alerting System

A production-grade monitoring and failure recovery system for Snowflake Snowpipe that automatically detects ingestion failures, performs intelligent retries, and sends Slack alerts when manual intervention is required.

##  Problem Statement

Snowflake Snowpipe lacks native failure handling, creating operational gaps:
- Failed file loads go undetected for hours or days
- No automatic retry mechanism for transient failures
- Manual monitoring costs $400+/month in engineering time
- Native Snowflake Tasks solution costs $40-60/month per pipe

##  Solution

Automated monitoring system that:
- **Detects** failures within 5 minutes via COPY_HISTORY polling
- **Retries** failed loads automatically (max 3 attempts)
- **Alerts** engineering team via Slack when manual intervention required
- **Tracks** retry attempts and failure patterns in audit log
- **Costs 87% less** than native Snowflake Tasks ($5.55/month vs $50+/month)

##  Architecture

### Technology Stack
- **Cloud Storage:** AWS S3
- **Event Trigger:** AWS SNS
- **Data Warehouse:** Snowflake (Snowpipe auto-ingest)
- **Orchestration:** n8n workflow automation (Railway-hosted)
- **Alerting:** Slack webhooks

### Data Flow

```
┌─────────────┐
│   AWS S3    │  File upload triggers event
│   Bucket    │
└──────┬──────┘
       │
       ▼ S3 Event Notification
┌─────────────┐
│   AWS SNS   │  Publishes to Snowpipe
│   Topic     │
└──────┬──────┘
       │
       ▼ Subscribe
┌──────────────────────────────────┐
│      Snowflake Snowpipe          │
│  ┌────────────────────────────┐  │
│  │  AUTO_INGEST = TRUE        │  │
│  │  Loads to staging table    │  │
│  └────────────────────────────┘  │
│                                  │
│  COPY_HISTORY tracks attempts   │
└──────────────┬───────────────────┘
               │
               ▼ Poll every 5 min
┌──────────────────────────────────┐
│      n8n Monitoring Workflow     │
│  ┌────────────────────────────┐  │
│  │ 1. Query COPY_HISTORY      │  │
│  │ 2. Check retry count       │  │
│  │ 3. IF retry < 3:           │  │
│  │    → ALTER PIPE REFRESH    │  │
│  │    → Log retry attempt     │  │
│  │    → Slack notification    │  │
│  │ 4. IF retry >= 3:          │  │
│  │    → Slack critical alert  │  │
│  └────────────────────────────┘  │
└──────────────┬───────────────────┘
               │
               ▼ Alerts
          ┌─────────┐
          │  Slack  │
          └─────────┘
```

##  Features

 **Intelligent Auto-Retry Logic** - Up to 3 automatic retry attempts with failure tracking  
 **Real-Time Slack Notifications** - Immediate alerts for retries and critical failures  
 **Complete Audit Trail** - All retry attempts logged in `snowpipe_failure_logs` table  
 **Cost Optimized** - $5.55/month vs $50+ with Snowflake Tasks (87% savings)  
 **Scalable Architecture** - Single workflow handles multiple pipes  
 **Production Ready** - Error handling, idempotency, SQL injection protection  

##  Cost Analysis

### Monthly Cost Breakdown

| Component | Cost | Notes |
|-----------|------|-------|
| **AWS S3** | $0.05 | Storage + requests |
| **AWS SNS** | $0.01 | Event notifications |
| **Snowflake Snowpipe** | $0.01 | Per-file loading |
| **Snowflake Warehouse** | $0.48 | X-Small, query execution |
| **n8n (Railway)** | $5.00 | Workflow hosting |
| **Slack** | $0.00 | Free webhooks |
| **Total** | **$5.55/month** | |

### Cost Comparison

| Solution | Monthly Cost | Savings |
|----------|--------------|---------|
| **This System** | $5.55 | Baseline |
| Snowflake Tasks | $50-60 | 87% more expensive |
| Manual Monitoring (2hr/week @ $50/hr) | $400 | 98% more expensive |

**Production Scaling:** 10 pipes, 1000 files/day = ~$7.28/month (still 85% cheaper than Tasks)


##  Quick Start

### Prerequisites

- Snowflake account with ACCOUNTADMIN privileges
- AWS account (S3, SNS access)
- Railway account (for n8n hosting) or self-hosted n8n
- Slack workspace with webhook permissions

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/snowpipe-auto-retry
cd snowpipe-auto-retry
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with your credentials
```

Required variables:
```bash
SNOWFLAKE_ACCOUNT=your-account.region
SNOWFLAKE_USER=n8n_monitor
SNOWFLAKE_PASSWORD=your-password
AWS_ACCOUNT_ID=123456789012
S3_BUCKET=your-bucket-name
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### 3. Set Up Snowflake Infrastructure

```bash
# Run SQL scripts in order
snowsql -f snowflake/01-database-setup.sql
snowsql -f snowflake/02-tables.sql
snowsql -f snowflake/03-pipe.sql
snowsql -f snowflake/04-permissions.sql
```

### 4. Configure AWS

**Create S3 bucket with folder structure:**
```
your-bucket-name/
├── inbound/       # Landing zone for new files
├── processed/     # Successfully loaded files
└── failed/        # Failed files for investigation
```

**Create SNS topic and configure S3 event notifications** (see [AWS Setup Guide](./docs/aws-setup.md))

### 5. Deploy n8n Workflow

1. Import `n8n/Snowpipe_Failure_Monitor_TEMPLATE.json` into n8n
2. Update Snowflake credentials
3. Update Slack webhook URL
4. Change Manual Trigger to Schedule Trigger (5-30 min interval)
5. Activate workflow

### 6. Test the System

Upload test files to S3:
```bash
# Good file (should load successfully)
aws s3 cp test-data/call_logs_good_001.csv s3://your-bucket/inbound/

# Bad file (should trigger retry workflow)
aws s3 cp test-data/call_logs_bad_schema.csv s3://your-bucket/inbound/
```

Monitor results:
```sql
-- Check load history
SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'staging_call_logs',
  START_TIME => DATEADD(hours, -1, CURRENT_TIMESTAMP())
));

-- Check retry log
SELECT * FROM snowpipe_failure_logs
ORDER BY failure_time DESC;
```

##  How It Works

### Workflow Logic

```javascript
// Pseudocode
EVERY 5 MINUTES:
  failures = query COPY_HISTORY WHERE status = 'LOAD_FAILED'
  
  FOR EACH failure:
    retry_count = lookup in snowpipe_failure_logs
    
    IF retry_count < 3:
      ALTER PIPE REFRESH  // Attempt reload
      INSERT INTO snowpipe_failure_logs (retry_count + 1)
      SEND Slack notification: "Auto-Retry #{retry_count + 1}"
    
    ELSE:
      SEND Slack critical alert: "Manual Intervention Required"
      UPDATE snowpipe_failure_logs SET notified = TRUE
```

### Key Components

**1. Failure Detection**
```sql
-- Query COPY_HISTORY for failed loads
SELECT file_name, status, error_message, last_load_time
FROM INFORMATION_SCHEMA.COPY_HISTORY(...)
WHERE status = 'LOAD_FAILED'
```

**2. Retry Tracking**
```sql
-- Track retry attempts
CREATE TABLE snowpipe_failure_logs (
  log_id NUMBER AUTOINCREMENT PRIMARY KEY,
  pipe_name VARCHAR(100),
  file_name VARCHAR(500),
  retry_count NUMBER,
  error_message VARCHAR(5000),
  failure_time TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  notified BOOLEAN DEFAULT FALSE
);
```

**3. Auto-Retry**
```sql
-- Trigger Snowpipe reload
ALTER PIPE call_logs_pipe REFRESH;
```

**4. Alerting**
- **Retry attempts (1-3):** Slack notification with retry number and error details
- **Exhausted retries (>3):** Critical alert with manual intervention flag

##  Testing Scenarios

### Test Case 1: Schema Mismatch
**File:** `call_logs_bad_schema.csv` (7 columns instead of 8)  
**Expected:** LOAD_FAILED → Auto-Retry #1 → Slack notification  
**Result:** Retry logged in `snowpipe_failure_logs`

### Test Case 2: Data Type Error
**File:** `call_logs_bad_datatype.csv` (text in NUMBER field)  
**Expected:** LOAD_FAILED → Auto-Retry #1 → Slack notification  
**Result:** Error message captured, retry attempted

### Test Case 3: Retry Exhaustion
**Setup:** Force `retry_count = 3` in database  
**Expected:** Workflow sends critical alert (no retry)  
**Result:** Slack critical notification, `notified = TRUE`

### Test Case 4: Successful Load
**File:** `call_logs_good_001.csv`  
**Expected:** LOADED status, no alerts  
**Result:** Data in `staging_call_logs`, no workflow action

##  Screenshots

### Successful Auto-Retry Notification
![Auto-Retry Slack Alert](./docs/screenshots/slack-retry.png)

*Slack notification showing automatic retry attempt #1 with error details*

### Critical Alert (Manual Intervention Required)
![Critical Failure Alert](./docs/screenshots/slack-critical.png)

*Critical alert after 3 failed retry attempts*

### n8n Workflow Canvas
![n8n Workflow](./docs/screenshots/n8n-workflow.png)

*Complete workflow showing failure detection, retry logic, and alerting nodes*

##  Documentation

- [Cost Analysis](./docs/cost-analysis.md) - Detailed cost breakdown and comparisons
- [AWS Setup Guide](./docs/aws-setup.md) - S3, SNS, IAM configuration
- [Snowflake Setup Guide](./docs/snowflake-setup.md) - Database, tables, pipe creation
- [n8n Workflow Guide](./docs/n8n-setup.md) - Workflow import and configuration
- [Troubleshooting](./docs/troubleshooting.md) - Common issues and solutions

##  Configuration

### Retry Policy

Adjust retry limits in n8n workflow:
```javascript
// In "Process Failures" node
should_retry: retryCount < 3  // Change 3 to desired max retries
```

### Monitoring Interval

Update Schedule Trigger in n8n:
```
Default: Every 5 minutes
Cost-optimized: Every 30 minutes (reduces warehouse usage)
Real-time: Every 1 minute (increases cost)
```

### Alert Thresholds

Customize Slack notifications:
```json
// Retry notification
"text": " Auto-Retry #{{ retry_count + 1 }}"

// Critical notification (adjust retry threshold)
"text": " FAILURE - 3/3 retries exhausted"
```

##  Security Best Practices

-  Store credentials in n8n credential manager (not in workflow JSON)
-  Use Snowflake service accounts with minimal privileges
-  Rotate AWS IAM access keys every 90 days
-  Enable Snowflake MFA for admin accounts
-  Use HTTPS for all webhook URLs
-  Implement IP whitelisting for n8n instance
-  Never commit `.env` files to version control

##  Limitations

- **COPY_HISTORY retention:** 64 days (older failures not detected)
- **Snowpipe idempotency:** Same file (name+size+timestamp) won't reload unless forced
- **n8n downtime:** Failures during outage won't be retried until next execution
- **Retry effectiveness:** If file is corrupted, retries will continue failing
- **Single region:** AWS and Snowflake must be in same region for low latency

##  Future Enhancements

- [ ] **Exponential backoff** - Increase delay between retries (5min → 15min → 30min)
- [ ] **Multi-pipe monitoring** - Centralized monitoring for multiple Snowpipes
- [ ] **Auto-quarantine** - Move failed files to S3 `failed/` folder after max retries
- [ ] **Grafana dashboard** - Visualization of failure rates, retry success, trends
- [ ] **PagerDuty integration** - Escalation for critical failures
- [ ] **File validation** - Pre-load schema validation to prevent bad uploads
- [ ] **Email alerts** - Secondary notification channel
- [ ] **Retry success tracking** - Measure which failures resolved after retry vs manual fix

##  Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

##  License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Snowflake documentation for COPY_HISTORY and Snowpipe best practices
- n8n community for workflow automation patterns
- Railway for affordable n8n hosting

## Author

**King**  
Analytics Engineer | Data Engineering Portfolio


---

**Built as part of Analytics Engineering portfolio demonstrating:**
- Production operations thinking (monitoring, alerting, failure handling)
- Cost optimization (87% savings vs native alternatives)
- Multi-tool integration (Snowflake + AWS + n8n + Slack)
- Real-world data engineering challenges in BPO/enterprise environments

**Target roles:** Analytics Engineer, Data Engineer (Philippines + Remote)

---

 **If you found this project helpful, please consider giving it a star!**
