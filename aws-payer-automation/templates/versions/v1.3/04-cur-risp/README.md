# Module 4: RISP CUR Export

## Overview
This module creates a Legacy Cost and Usage Report (CUR) export for RISP (Reseller Incentive Support Program) without pro forma pricing configuration.

## Resources Created
- **S3 Bucket**: Named "bip-risp-cur-{AccountId}" for storing RISP CUR data
- **CUR Export**: Legacy format with standard AWS pricing
- **Lambda Function**: Handles S3 bucket and CUR creation
- **IAM Role**: Provides necessary permissions for Lambda execution

## Features
- Creates S3 bucket with security best practices
- Sets up bucket policy for AWS billing service access
- Creates Legacy CUR with Parquet format
- Includes Athena integration for data analysis
- Uses standard AWS pricing (no pro forma)

## Dependencies
- Can be deployed independently of other modules
- CUR service must be available (us-east-1 only)
- AWS Organizations should be enabled for proper account identification

## Deployment
```bash
aws cloudformation create-stack \
  --stack-name payer-cur-risp-$(date +%s) \
  --template-body file://cur_export_risp.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

## Outputs
- `RISPBucketName`: Name of the S3 bucket for RISP CUR data
- `RISPBucketRegion`: Region of the S3 bucket (us-east-1)
- `RISPReportName`: Name of the RISP CUR report (risp-{AccountId})
- `RISPCURArn`: ARN of the RISP CUR report

## Key Differences from Pro forma CUR
- No BillingViewArn parameter (uses standard AWS pricing)
- Separate S3 bucket with "risp" prefix
- Report name includes "risp-" prefix for identification
- Independent of BillingConductor configuration

## Notes
- CUR can only be created in us-east-1 region
- S3 bucket has versioning enabled and public access blocked
- Reports are generated daily in Parquet format
- Athena integration is automatically configured
- This CUR shows actual AWS list prices, not pro forma prices