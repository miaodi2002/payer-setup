#!/bin/bash
# 生产部署环境变量 - Mon Aug 11 15:32:05 JST 2025
# 由pre-deployment-check.sh自动生成

# 基础环境
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"

# AWS环境信息
export CURRENT_ACCOUNT_ID="534877455433"
export ORGANIZATION_ID="o-o8v5xudnuh"
export MASTER_ACCOUNT_ID="534877455433"

# 项目路径
export PROJECT_PATH="/Users/di.miao/Work/payer-setup/aws-payer-automation"
export DEPLOYMENT_PATH="/Users/di.miao/Work/payer-setup/payer-deployments"

# Organizations结构 (需要时可用)
export ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text 2>/dev/null || echo "")

echo "✅ 生产环境变量已加载"
echo "当前账户: $CURRENT_ACCOUNT_ID"
echo "Organization: $ORGANIZATION_ID"
echo "Master账户: $MASTER_ACCOUNT_ID"
echo "时间戳: $TIMESTAMP"
