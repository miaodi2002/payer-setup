# Module 1: OU and SCP Setup

## Overview
This module creates the organizational structure and applies Service Control Policies (SCPs) to control access and prevent unwanted actions across the AWS Organization.

## Resources Created
- **Free OU**: For accounts with basic restrictions
- **Block OU**: For accounts with strict access controls
- **Normal OU**: For standard business accounts with moderate restrictions

## SCPs Applied
- **DenyAccessNonPayAsGo_DenyBigSize_ACM**: Prevents reserved instances, large EC2 instances, and ACM CA operations
- **DenyLeaveOrganization**: Prevents accounts from leaving the organization
- **DenyRoot**: Blocks all root user actions
- **DenyRootChange**: Prevents email address changes
- **DenySupport**: Blocks support plan changes
- **DenyShield**: Prevents Shield subscription updates
- **Deny_CloudFront**: Restricts CloudFront access for specific user patterns

## Parameters
- `RootId`: The AWS Organizations root ID (required)

## Deployment
```bash
aws cloudformation create-stack \
  --stack-name payer-ou-scp-$(date +%s) \
  --template-body file://auto_SCP_1.yaml \
  --parameters ParameterKey=RootId,ParameterValue=r-xxxx \
  --capabilities CAPABILITY_NAMED_IAM
```

## Outputs
- `FreeOUId`: ID of the Free OU
- `BlockOUId`: ID of the Block OU  
- `NormalOUId`: ID of the Normal OU