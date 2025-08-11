# Module 2: BillingConductor Setup

## Overview
This module creates a new AWS account with "+bills" email alias and sets up a BillingConductor BillingGroup for pro forma pricing.

## Resources Created
- **New AWS Account**: Named "{MasterAccountName}-Bills" with email alias
- **BillingGroup**: Named "Bills" with AWS_STANDARD pricing plan
- **Lambda Function**: Handles account creation and billing group setup
- **IAM Role**: Provides necessary permissions for Lambda execution

## Features
- Automatic email alias generation (+bills)
- Conflict resolution for duplicate emails (adds numeric suffix)
- 30-minute timeout for account creation
- Error handling and rollback protection

## Dependencies
- AWS Organizations must be enabled
- BillingConductor service must be available in the region
- Appropriate IAM permissions for account creation

## Deployment
```bash
aws cloudformation create-stack \
  --stack-name payer-billing-conductor-$(date +%s) \
  --template-body file://billing_conductor.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

## Outputs
- `NewAccountId`: ID of the newly created account
- `NewAccountEmail`: Email address of the new account
- `BillingGroupArn`: ARN of the created BillingGroup

## Notes
- Account creation can take up to 30 minutes
- The Lambda function will not delete accounts on stack deletion
- Email conflicts are automatically resolved with numeric suffixes