# Module 3: Pro forma CUR Export

## Overview
This module creates a Legacy Cost and Usage Report (CUR) export with pro forma pricing using the BillingGroup created in Module 2.

## Resources Created
- **S3 Bucket**: Named "bip-cur-{AccountId}" for storing CUR data
- **CUR Export**: Legacy format with pro forma pricing
- **Lambda Function**: Handles S3 bucket and CUR creation
- **IAM Role**: Provides necessary permissions for Lambda execution

## Features
- Creates S3 bucket with security best practices
- Sets up bucket policy for AWS billing service access
- Creates Legacy CUR with Parquet format
- Includes Athena integration for data analysis
- Uses pro forma pricing via BillingGroup ARN

## Dependencies
- Module 2 (BillingConductor) must be deployed first
- BillingGroupArn parameter from Module 2 output
- CUR service must be available (us-east-1 only)

## Parameters
- `BillingGroupArn`: ARN of the BillingGroup from Module 2 (required)

## Deployment
```bash
# Get BillingGroupArn from Module 2 stack
BILLING_GROUP_ARN=$(aws cloudformation describe-stacks \
  --stack-name payer-billing-conductor-xyz \
  --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' \
  --output text)

aws cloudformation create-stack \
  --stack-name payer-cur-proforma-$(date +%s) \
  --template-body file://cur_export_proforma.yaml \
  --parameters ParameterKey=BillingGroupArn,ParameterValue=$BILLING_GROUP_ARN \
  --capabilities CAPABILITY_NAMED_IAM
```

## Outputs
- `BucketName`: Name of the S3 bucket for CUR data
- `BucketRegion`: Region of the S3 bucket (us-east-1)
- `ReportName`: Name of the CUR report (Account ID)
- `CURArn`: ARN of the CUR report

## Notes
- CUR can only be created in us-east-1 region
- S3 bucket has versioning enabled and public access blocked
- Reports are generated daily in Parquet format
- Athena integration is automatically configured