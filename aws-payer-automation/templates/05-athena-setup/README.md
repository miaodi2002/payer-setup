# Module 5: Athena Setup

## Overview
This module creates a comprehensive Athena environment for analyzing both Pro forma and RISP CUR data. It automates the setup of Glue databases, crawlers, and Lambda functions for real-time data discovery and updates.

## Resources Created
- **Glue Database**: `athenacurcfn_{account_id}` - Unified database for all CUR tables
- **Glue Crawlers**: 
  - `AWSCURCrawler-{account_id}` - For Pro forma CUR data
  - `AWSRISPCURCrawler-{account_id}` - For RISP CUR data
- **Lambda Functions**:
  - `CreateAthenaEnvironment` - Main setup orchestrator
  - `AWSCURInitializer-{account_id}` - Crawler trigger function
  - `AWSS3CURNotification` - S3 event processor
- **IAM Roles**: Crawler execution roles with appropriate permissions
- **Status Tables**: Track CUR data generation status
- **S3 Event Notifications**: Automatic data discovery triggers

## Features
- **Dual CUR Support**: Handles both Pro forma and RISP CUR data in the same database
- **Automatic Discovery**: S3 events trigger crawler execution for new data
- **Status Tracking**: Dedicated tables to monitor CUR data availability
- **Security Best Practices**: Least privilege IAM roles and policies
- **Error Resilience**: Comprehensive error handling and retry logic

## Dependencies
- Module 3 (Pro forma CUR Export) must be deployed successfully
- Module 4 (RISP CUR Export) must be deployed successfully
- Both CUR exports must be generating data in S3

## Parameters
- `ProformaBucketName`: S3 bucket name for Pro forma CUR data (from Module 3)
- `RISPBucketName`: S3 bucket name for RISP CUR data (from Module 4)
- `ProformaReportName`: Pro forma CUR report name (from Module 3)
- `RISPReportName`: RISP CUR report name (from Module 4)

## Deployment
```bash
# Get parameters from previous modules
PROFORMA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-proforma-* \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

RISP_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-risp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPBucketName`].OutputValue' \
  --output text)

PROFORMA_REPORT=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-proforma-* \
  --query 'Stacks[0].Outputs[?OutputKey==`ReportName`].OutputValue' \
  --output text)

RISP_REPORT=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-risp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPReportName`].OutputValue' \
  --output text)

# Deploy Module 5
aws cloudformation create-stack \
  --stack-name payer-athena-setup-$(date +%s) \
  --template-body file://athena_setup.yaml \
  --parameters \
    ParameterKey=ProformaBucketName,ParameterValue=$PROFORMA_BUCKET \
    ParameterKey=RISPBucketName,ParameterValue=$RISP_BUCKET \
    ParameterKey=ProformaReportName,ParameterValue=$PROFORMA_REPORT \
    ParameterKey=RISPReportName,ParameterValue=$RISP_REPORT \
  --capabilities CAPABILITY_NAMED_IAM
```

## Resources Structure

### Database and Tables
```
athenacurcfn_{account_id}/
├── {account_id}                           # Pro forma CUR table
├── risp_{account_id}                      # RISP CUR table  
├── cost_and_usage_data_status             # Pro forma status table
└── risp_cost_and_usage_data_status        # RISP status table
```

### IAM Roles
- **AWSCURCrawlerRole-{account_id}**: Glue crawler execution with S3 access
- **AWSCURCrawlerLambdaExecutor**: Lambda function to start crawlers
- **AWSS3CURLambdaExecutor**: S3 notification processing

### Lambda Functions
- **CreateAthenaEnvironment**: CloudFormation custom resource handler
- **AWSCURInitializer-{account_id}**: Starts specific crawlers on demand
- **AWSS3CURNotification**: Processes S3 events and triggers crawlers

## Automation Flow

1. **S3 Event**: New CUR data files are created in S3
2. **Notification**: S3 event triggers `AWSS3CURNotification` Lambda
3. **Analysis**: Lambda analyzes the S3 path to determine crawler type
4. **Invocation**: Lambda invokes `AWSCURInitializer` with crawler name
5. **Crawler**: Glue crawler runs to discover new data structure
6. **Table Update**: Athena tables are updated with new partitions

## Verification

### Check Database and Tables
```bash
# List databases
aws glue get-databases

# List tables in CUR database
DATABASE_NAME="athenacurcfn_$(aws sts get-caller-identity --query Account --output text)"
aws glue get-tables --database-name $DATABASE_NAME

# Check crawler status
aws glue get-crawler --name AWSCURCrawler-$(aws sts get-caller-identity --query Account --output text)
aws glue get-crawler --name AWSRISPCURCrawler-$(aws sts get-caller-identity --query Account --output text)
```

### Check Lambda Functions
```bash
# List Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `CUR`)].FunctionName'

# Check S3 notifications
PROFORMA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-proforma-* \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

aws s3api get-bucket-notification-configuration --bucket $PROFORMA_BUCKET
```

## Outputs
- `DatabaseName`: Glue database name for Athena queries
- `ProformaCrawlerName`: Name of the Pro forma CUR crawler
- `RISPCrawlerName`: Name of the RISP CUR crawler

## Query Examples

### Query Pro forma Data
```sql
SELECT 
    line_item_product_code,
    line_item_usage_type,
    SUM(line_item_blended_cost) as total_cost
FROM athenacurcfn_123456789012.123456789012
WHERE year = '2024' AND month = '01'
GROUP BY line_item_product_code, line_item_usage_type
ORDER BY total_cost DESC;
```

### Query RISP Data
```sql
SELECT 
    line_item_product_code,
    SUM(line_item_unblended_cost) as total_cost
FROM athenacurcfn_123456789012.risp_123456789012
WHERE year = '2024' AND month = '01'
GROUP BY line_item_product_code
ORDER BY total_cost DESC;
```

### Compare Pro forma vs RISP Pricing
```sql
SELECT 
    p.line_item_product_code,
    SUM(p.line_item_blended_cost) as proforma_cost,
    SUM(r.line_item_unblended_cost) as risp_cost,
    SUM(r.line_item_unblended_cost) - SUM(p.line_item_blended_cost) as cost_difference
FROM athenacurcfn_123456789012.123456789012 p
JOIN athenacurcfn_123456789012.risp_123456789012 r
    ON p.line_item_product_code = r.line_item_product_code
    AND p.year = r.year 
    AND p.month = r.month
WHERE p.year = '2024' AND p.month = '01'
GROUP BY p.line_item_product_code
ORDER BY cost_difference DESC;
```

## Troubleshooting

### Common Issues

1. **Crawler not starting**: Check IAM roles and S3 permissions
2. **Tables not created**: Verify CUR data exists in S3
3. **S3 notifications not working**: Check Lambda permissions and S3 configuration
4. **Empty query results**: Ensure crawlers have run successfully

### Debug Commands
```bash
# Check crawler last run
aws glue get-crawler-metrics --crawler-name-list AWSCURCrawler-$(aws sts get-caller-identity --query Account --output text)

# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/AWSCURInitializer

# Test crawler manually
aws glue start-crawler --name AWSCURCrawler-$(aws sts get-caller-identity --query Account --output text)
```

## Notes
- Tables are automatically partitioned by year/month
- Initial crawler run may take 10-15 minutes
- S3 notifications may take a few minutes to configure
- Status tables help track CUR data availability
- All resources follow AWS naming conventions