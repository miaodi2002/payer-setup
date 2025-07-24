#!/bin/bash
# AWS Payer Automation 测试变量 - 模组1
# 生成时间: Tue Jul 22 19:57:05 JST 2025

# 基础环境变量
export REGION="us-east-1" 
export AWS_DEFAULT_REGION="us-east-1"
export MASTER_ACCOUNT_ID="730335480018"

# 模组1 - OU和SCP
export MODULE1_STACK_NAME="payer-ou-scp-1753181540"
export NORMAL_OU_ID="ou-e2ag-maqpcur7"
export FREE_OU_ID="ou-e2ag-w5czdwg0"
export BLOCK_OU_ID="ou-e2ag-u67ud8w6"
export ROOT_ID="r-e2ag"
export ORGANIZATION_ID="o-t4quxjx4cr"

echo "✅ 模组1测试变量已加载"
echo "Master Account ID: $MASTER_ACCOUNT_ID"
echo "Normal OU ID: $NORMAL_OU_ID"
echo "Free OU ID: $FREE_OU_ID"
echo "Block OU ID: $BLOCK_OU_ID"

# 模组2 - 账户和BillingGroup
export NEW_ACCOUNT_ID="058316962835"
export NEW_ACCOUNT_EMAIL="zuby+bills@healthcapartnersltd.co.uk"
export NEW_ACCOUNT_NAME="zubyhealth-Bills"
export BILLING_GROUP_ARN="arn:aws:billingconductor::730335480018:billinggroup/058316962835"
export BILLING_GROUP_NAME="billing-group-1753182274"
export PRICING_PLAN_ARN="arn:aws:billingconductor::730335480018:pricingplan/BqdlyxYBRx"
export MODULE2_STACK_NAME="payer-billing-conductor-1753181976"

echo "✅ 模组2测试变量已加载"
echo "New Account ID: $NEW_ACCOUNT_ID"
echo "BillingGroup ARN: $BILLING_GROUP_ARN"
export PROFORMA_BUCKET_NAME='bip-cur-730335480018'
export PROFORMA_REPORT_NAME='730335480018'
export MODULE3_STACK_NAME='payer-cur-proforma-1753182555'

# ✅ 模组4测试变量已加载
export RISP_BUCKET_NAME='bip-risp-cur-730335480018'
export RISP_REPORT_NAME='risp-730335480018'
export MODULE4_STACK_NAME='payer-cur-risp-1753182831'
# 模组5 - Athena环境设置
export ATHENA_DATABASE_NAME='athenacurcfn_730335480018'
export PROFORMA_CRAWLER_NAME='AWSCURCrawler-730335480018'
export RISP_CRAWLER_NAME='AWSRISPCURCrawler-730335480018'
export MODULE5_STACK_NAME='payer-athena-final-1753230578'

echo "✅ 模组5测试变量已加载"
echo "Athena Database: $ATHENA_DATABASE_NAME"
echo "Pro forma Crawler: $PROFORMA_CRAWLER_NAME"
echo "RISP Crawler: $RISP_CRAWLER_NAME"
