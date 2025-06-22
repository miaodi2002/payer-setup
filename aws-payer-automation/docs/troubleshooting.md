# AWS Payer自动化初始化 - 故障排除指南

## 概述

本指南提供AWS Payer自动化初始化项目的全面故障排除方法，涵盖常见问题、诊断步骤和解决方案。

## 通用诊断流程

### 1. 初始诊断步骤

#### 环境检查清单
```bash
#!/bin/bash
# diagnostic-check.sh

echo "=== AWS Payer Automation Diagnostic Check ==="

# 1. AWS CLI配置
echo "1. AWS CLI Configuration:"
aws --version
aws sts get-caller-identity || echo "❌ AWS CLI not configured"

# 2. 权限检查
echo -e "\n2. Permissions Check:"
aws organizations describe-organization &>/dev/null && echo "✅ Organizations access" || echo "❌ Organizations access denied"
aws cloudformation list-stacks &>/dev/null && echo "✅ CloudFormation access" || echo "❌ CloudFormation access denied"
aws iam get-account-summary &>/dev/null && echo "✅ IAM access" || echo "❌ IAM access denied"

# 3. 区域检查
echo -e "\n3. Region Check:"
echo "Current region: $(aws configure get region)"
echo "Required region: us-east-1"

# 4. 模板文件检查
echo -e "\n4. Template Files:"
for template in templates/*/*.yaml; do
    if [ -f "$template" ]; then
        echo "✅ $template exists"
    else
        echo "❌ $template missing"
    fi
done

# 5. 脚本权限检查
echo -e "\n5. Script Permissions:"
for script in scripts/*.sh; do
    if [ -x "$script" ]; then
        echo "✅ $script executable"
    else
        echo "❌ $script not executable"
    fi
done

echo -e "\nDiagnostic check completed"
```

### 2. 错误信息收集

#### 日志收集脚本
```bash
#!/bin/bash
# collect-logs.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="troubleshooting_logs_$TIMESTAMP"
mkdir -p $LOG_DIR

echo "Collecting diagnostic information..."

# CloudFormation栈信息
echo "Collecting CloudFormation stack information..."
aws cloudformation list-stacks > $LOG_DIR/all_stacks.json
aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, `payer-`)]' > $LOG_DIR/payer_stacks.json

# 栈事件和资源
for stack in $(aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, `payer-`)].StackName' --output text); do
    echo "Collecting events for stack: $stack"
    aws cloudformation describe-stack-events --stack-name $stack > $LOG_DIR/${stack}_events.json
    aws cloudformation list-stack-resources --stack-name $stack > $LOG_DIR/${stack}_resources.json
    aws cloudformation describe-stacks --stack-name $stack > $LOG_DIR/${stack}_details.json
done

# Lambda日志
echo "Collecting Lambda logs..."
for log_group in $(aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/' --query 'logGroups[?contains(logGroupName, `payer`) || contains(logGroupName, `Lambda`) || contains(logGroupName, `Attach`) || contains(logGroupName, `Create`)].logGroupName' --output text); do
    echo "Collecting logs from: $log_group"
    aws logs describe-log-streams --log-group-name $log_group --order-by LastEventTime --descending --max-items 5 > $LOG_DIR/$(basename $log_group)_streams.json
done

# Organizations信息
echo "Collecting Organizations information..."
aws organizations describe-organization > $LOG_DIR/organization.json
aws organizations list-roots > $LOG_DIR/roots.json
aws organizations list-policies --filter SERVICE_CONTROL_POLICY > $LOG_DIR/scp_policies.json

# BillingConductor信息
echo "Collecting BillingConductor information..."
aws billingconductor list-billing-groups --region us-east-1 > $LOG_DIR/billing_groups.json 2>/dev/null || echo "BillingConductor not accessible" > $LOG_DIR/billing_groups.json

# CUR信息
echo "Collecting CUR information..."
aws cur describe-report-definitions --region us-east-1 > $LOG_DIR/cur_reports.json 2>/dev/null || echo "CUR not accessible" > $LOG_DIR/cur_reports.json

# S3存储桶信息
echo "Collecting S3 information..."
aws s3api list-buckets --query 'Buckets[?contains(Name, `bip-`)]' > $LOG_DIR/s3_buckets.json

echo "Logs collected in directory: $LOG_DIR"
echo "Please include this directory when reporting issues"
```

## 模块特定故障排除

### Module 1: OU和SCP故障排除

#### 常见问题 1: Root ID获取失败
```bash
# 症状
aws organizations list-roots
# 错误: AccessDeniedException

# 诊断
echo "Checking Organizations access..."
aws sts get-caller-identity
aws organizations describe-organization

# 解决方案
# 1. 确认账户是Organizations管理账户
# 2. 检查IAM权限是否包含organizations:*
# 3. 确认Organizations服务已启用
```

#### 常见问题 2: SCP策略创建失败
```bash
# 症状
ERROR: "Policy type SERVICE_CONTROL_POLICY is not enabled"
ERROR: "PolicyTypeNotEnabledException when calling the AttachPolicy operation"

# 诊断
aws organizations describe-organization --query 'Organization.AvailablePolicyTypes'

# 解决方案 (自动化)
# ✅ 最新版本的模板已自动处理此问题
# Lambda函数会自动启用SCP并重试策略附加

# 手动解决方案（如果需要）
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations enable-policy-type \
    --root-id $ROOT_ID \
    --policy-type SERVICE_CONTROL_POLICY

# 等待几秒钟后重新部署栈
```

#### 常见问题 3: Lambda执行超时
```bash
# 症状
CloudFormation显示Custom::InvokeLambda失败

# 诊断
LOG_GROUP="/aws/lambda/AttachSCPToOU"
aws logs describe-log-streams --log-group-name $LOG_GROUP --order-by LastEventTime --descending --max-items 1

# 查看最新日志
STREAM_NAME=$(aws logs describe-log-streams --log-group-name $LOG_GROUP --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text)
aws logs get-log-events --log-group-name $LOG_GROUP --log-stream-name $STREAM_NAME

# 解决方案
# 1. 检查SCP策略JSON格式
# 2. 确认目标OU存在
# 3. 验证Lambda权限
```

### Module 2: BillingConductor故障排除

#### 常见问题 1: 账户创建失败
```bash
# 症状
ERROR: "Email address already in use"

# 诊断
aws organizations list-accounts --query 'Accounts[].Email' | grep -i bills

# 手动检查邮箱冲突
EMAIL="your-email+bills@domain.com"
aws organizations list-accounts --query "Accounts[?Email=='$EMAIL']"

# 解决方案
# Lambda会自动处理邮箱冲突，添加数字后缀
# 如果仍失败，检查Lambda日志获取详细错误信息
```

#### 常见问题 2: 账户创建超时
```bash
# 症状
Lambda执行超时（15分钟后）

# 诊断
aws organizations list-create-account-status

# 获取具体创建状态
REQUEST_ID="car-xxxxxxxxxxxxxxxx"
aws organizations describe-create-account-status --create-account-request-id $REQUEST_ID

# 解决方案选项
# 1. 等待更长时间（最多30分钟）
# 2. 检查AWS服务健康状态
# 3. 联系AWS支持如果持续失败
```

#### 常见问题 3: BillingConductor不可用
```bash
# 症状
ERROR: "Service is not available in this region"

# 诊断
aws billingconductor list-billing-groups --region us-east-1
aws billingconductor list-billing-groups --region us-west-2

# 解决方案
# BillingConductor可能在某些区域不可用
# 1. 确认在us-east-1区域部署
# 2. 检查AWS服务状态页面
# 3. 考虑申请BillingConductor访问权限
```

### Module 3: Pro forma CUR故障排除

#### 常见问题 1: BillingGroup ARN格式错误
```bash
# 症状
ERROR: "Invalid BillingGroup ARN"

# 诊断
echo "Provided ARN: $BILLING_GROUP_ARN"
echo "Expected format: arn:aws:billingconductor::ACCOUNT:billinggroup/GROUP_ID"

# 验证ARN
aws billingconductor list-billing-groups --region us-east-1 --query 'BillingGroups[].Arn'

# 解决方案
# 从Module 2栈输出重新获取正确的ARN
STACK_NAME=$(aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, `payer-billing-conductor-`)].StackName' --output text)
BILLING_GROUP_ARN=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' --output text)
```

#### 常见问题 2: S3存储桶创建失败
```bash
# 症状
ERROR: "Bucket name already exists"

# 诊断
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="bip-cur-$ACCOUNT_ID"
aws s3api head-bucket --bucket $BUCKET_NAME

# 解决方案
# 1. 删除现有存储桶（如果可以）
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $BUCKET_NAME

# 2. 或者修改模板使用不同的存储桶名称
```

#### 常见问题 3: CUR创建在错误区域
```bash
# 症状
ERROR: "CUR can only be created in us-east-1"

# 诊断
echo "Current region: $(aws configure get region)"
echo "Stack region: $AWS_DEFAULT_REGION"

# 解决方案
# 确保在us-east-1区域部署
export AWS_DEFAULT_REGION=us-east-1
aws configure set region us-east-1
```

### Module 4: RISP CUR故障排除

#### 常见问题 1: 重复的CUR报告名称
```bash
# 症状
ERROR: "Report name already exists"

# 诊断
aws cur describe-report-definitions --region us-east-1 --query 'ReportDefinitions[].ReportName'

# 解决方案
# 1. 删除现有报告（如果可以）
aws cur delete-report-definition --report-name "risp-$ACCOUNT_ID" --region us-east-1

# 2. 或者修改模板使用不同的报告名称
```

#### 常见问题 2: S3权限问题
```bash
# 症状
ERROR: "Access Denied" 在S3操作时

# 诊断
aws s3api get-bucket-policy --bucket "bip-risp-cur-$ACCOUNT_ID"
aws s3api get-bucket-acl --bucket "bip-risp-cur-$ACCOUNT_ID"

# 解决方案
# 检查Lambda IAM角色权限
ROLE_NAME="LambdaRISPCURExportRole"
aws iam get-role-policy --role-name $ROLE_NAME --policy-name CURAndS3Access
```

## 跨模块问题

### 问题 1: 栈间依赖失败
```bash
# 症状
ERROR: "Export BillingGroupArn cannot be found"

# 诊断
aws cloudformation list-exports --query 'Exports[?contains(Name, `BillingGroup`)]'

# 检查依赖栈状态
aws cloudformation describe-stacks --stack-name payer-billing-conductor-*

# 解决方案
# 1. 确认前置栈部署成功
# 2. 检查Export名称格式
# 3. 重新部署失败的栈
```

### 问题 2: 权限不足
```bash
# 症状
Multiple "AccessDenied" errors across modules

# 全面权限诊断
cat > check-permissions.sh << 'EOF'
#!/bin/bash
echo "=== Permission Check ==="

# Organizations权限
aws organizations describe-organization &>/dev/null && echo "✅ Organizations" || echo "❌ Organizations"

# CloudFormation权限  
aws cloudformation list-stacks &>/dev/null && echo "✅ CloudFormation" || echo "❌ CloudFormation"

# IAM权限
aws iam list-roles &>/dev/null && echo "✅ IAM" || echo "❌ IAM"

# Lambda权限
aws lambda list-functions &>/dev/null && echo "✅ Lambda" || echo "❌ Lambda"

# S3权限
aws s3 ls &>/dev/null && echo "✅ S3" || echo "❌ S3"

# CUR权限
aws cur describe-report-definitions --region us-east-1 &>/dev/null && echo "✅ CUR" || echo "❌ CUR"

# BillingConductor权限
aws billingconductor list-billing-groups --region us-east-1 &>/dev/null && echo "✅ BillingConductor" || echo "❌ BillingConductor"
EOF

chmod +x check-permissions.sh
./check-permissions.sh

# 解决方案
# 应用管理员权限或以下最小权限集：
# organizations:*, iam:*, cloudformation:*, lambda:*, s3:*, cur:*, billingconductor:*
```

## 恢复和清理程序

### 1. 部分失败恢复

#### 单模块重部署
```bash
#!/bin/bash
# redeploy-module.sh

MODULE=$1
if [ -z "$MODULE" ]; then
    echo "Usage: $0 <module_number>"
    exit 1
fi

echo "Redeploying Module $MODULE..."

# 删除失败的栈
FAILED_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_FAILED UPDATE_FAILED ROLLBACK_FAILED \
    --query "StackSummaries[?contains(StackName, 'payer-')].StackName" \
    --output text)

for stack in $FAILED_STACKS; do
    echo "Deleting failed stack: $stack"
    aws cloudformation delete-stack --stack-name $stack
    aws cloudformation wait stack-delete-complete --stack-name $stack
done

# 重新部署指定模块
case $MODULE in
    1)
        ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
        ./scripts/deploy-single.sh 1 --root-id $ROOT_ID
        ;;
    2)
        ./scripts/deploy-single.sh 2
        ;;
    3)
        BILLING_GROUP_ARN=$(get_billing_group_arn_from_stack)
        ./scripts/deploy-single.sh 3 --billing-group-arn $BILLING_GROUP_ARN
        ;;
    4)
        ./scripts/deploy-single.sh 4
        ;;
esac
```

### 2. 完全清理和重新开始

#### 彻底清理脚本
```bash
#!/bin/bash
# complete-cleanup.sh

echo "WARNING: This will delete ALL payer-related resources!"
read -p "Are you absolutely sure? Type 'DELETE EVERYTHING' to confirm: " confirm

if [ "$confirm" != "DELETE EVERYTHING" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo "Starting complete cleanup..."

# 1. 删除CloudFormation栈
echo "Deleting CloudFormation stacks..."
./scripts/cleanup.sh --delete-all --force

# 2. 手动清理残留资源
echo "Cleaning up residual resources..."

# 删除S3存储桶内容
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
for bucket in "bip-cur-$ACCOUNT_ID" "bip-risp-cur-$ACCOUNT_ID"; do
    if aws s3 ls s3://$bucket &>/dev/null; then
        echo "Emptying bucket: $bucket"
        aws s3 rm s3://$bucket --recursive
        aws s3api delete-bucket --bucket $bucket
    fi
done

# 删除CUR报告
echo "Deleting CUR reports..."
for report in "$ACCOUNT_ID" "risp-$ACCOUNT_ID"; do
    aws cur delete-report-definition --report-name $report --region us-east-1 2>/dev/null || true
done

# 清理BillingConductor资源
echo "Cleaning BillingConductor resources..."
for bg in $(aws billingconductor list-billing-groups --region us-east-1 --query 'BillingGroups[?Name==`Bills`].Arn' --output text); do
    aws billingconductor delete-billing-group --arn $bg --region us-east-1 2>/dev/null || true
done

# 注意：不删除创建的账户和OU，这些需要手动处理

echo "Cleanup completed"
echo "Note: Created accounts and OUs were not deleted and need manual cleanup"
```

### 3. 状态验证和健康检查

#### 部署后验证脚本
```bash
#!/bin/bash
# post-deployment-validation.sh

set -e

echo "=== Post-Deployment Validation ==="

# 1. 验证所有栈都成功
echo "1. Checking stack status..."
FAILED_STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?starts_with(StackName, 'payer-') && !contains(StackStatus, 'COMPLETE')].{Name:StackName,Status:StackStatus}" \
    --output text)

if [ -n "$FAILED_STACKS" ]; then
    echo "❌ Failed stacks found:"
    echo "$FAILED_STACKS"
    exit 1
else
    echo "✅ All stacks completed successfully"
fi

# 2. 验证OU结构
echo "2. Checking OU structure..."
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
OU_NAMES=$(aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID --query 'OrganizationalUnits[].Name' --output text)

for expected_ou in "Free" "Block" "Normal"; do
    if echo "$OU_NAMES" | grep -q "$expected_ou"; then
        echo "✅ OU $expected_ou exists"
    else
        echo "❌ OU $expected_ou missing"
        exit 1
    fi
done

# 3. 验证CUR报告
echo "3. Checking CUR reports..."
CUR_REPORTS=$(aws cur describe-report-definitions --region us-east-1 --query 'ReportDefinitions[].ReportName' --output text)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
for expected_cur in "$ACCOUNT_ID" "risp-$ACCOUNT_ID"; do
    if echo "$CUR_REPORTS" | grep -q "$expected_cur"; then
        echo "✅ CUR report $expected_cur exists"
    else
        echo "❌ CUR report $expected_cur missing"
        exit 1
    fi
done

# 4. 验证S3存储桶
echo "4. Checking S3 buckets..."
for bucket in "bip-cur-$ACCOUNT_ID" "bip-risp-cur-$ACCOUNT_ID"; do
    if aws s3 ls s3://$bucket &>/dev/null; then
        echo "✅ S3 bucket $bucket exists"
    else
        echo "❌ S3 bucket $bucket missing"
        exit 1
    fi
done

echo "✅ All validation checks passed!"
```

## 性能问题排查

### 1. 部署速度优化

#### 识别瓶颈
```bash
#!/bin/bash
# deployment-timing.sh

echo "Analyzing deployment timing..."

for stack in $(aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, `payer-`)].StackName' --output text); do
    echo "=== $stack ==="
    
    # 获取栈事件
    aws cloudformation describe-stack-events --stack-name $stack \
        --query 'StackEvents[?ResourceStatus==`CREATE_COMPLETE` || ResourceStatus==`CREATE_IN_PROGRESS`].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus}' \
        --output table
    
    # 计算总部署时间
    START_TIME=$(aws cloudformation describe-stack-events --stack-name $stack --query 'StackEvents[-1].Timestamp' --output text)
    END_TIME=$(aws cloudformation describe-stack-events --stack-name $stack --query 'StackEvents[0].Timestamp' --output text)
    
    echo "Start: $START_TIME"
    echo "End: $END_TIME"
done
```

### 2. 资源使用优化

#### Lambda性能分析
```bash
#!/bin/bash
# lambda-performance.sh

echo "Analyzing Lambda performance..."

for function in $(aws lambda list-functions --query 'Functions[?contains(FunctionName, `payer`) || contains(FunctionName, `Attach`) || contains(FunctionName, `Create`)].FunctionName' --output text); do
    echo "=== $function ==="
    
    # 获取函数配置
    aws lambda get-function-configuration --function-name $function \
        --query '{Memory:MemorySize,Timeout:Timeout,Runtime:Runtime}' \
        --output table
    
    # 获取最近的调用指标
    aws logs filter-log-events \
        --log-group-name "/aws/lambda/$function" \
        --start-time $(date -d '1 hour ago' +%s)000 \
        --filter-pattern "REPORT" \
        --query 'events[].message' \
        --output text | head -5
done
```

## 支持和升级

### 1. 收集支持信息

#### 支持包生成
```bash
#!/bin/bash
# generate-support-package.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUPPORT_DIR="support_package_$TIMESTAMP"
mkdir -p $SUPPORT_DIR

echo "Generating support package..."

# 基本信息
aws --version > $SUPPORT_DIR/aws_version.txt
aws sts get-caller-identity > $SUPPORT_DIR/caller_identity.json
aws configure list > $SUPPORT_DIR/aws_config.txt

# 收集完整日志
./collect-logs.sh
mv troubleshooting_logs_* $SUPPORT_DIR/

# 模板文件
cp -r templates/ $SUPPORT_DIR/

# 运行诊断
./diagnostic-check.sh > $SUPPORT_DIR/diagnostic_results.txt

# 创建压缩包
tar -czf "${SUPPORT_DIR}.tar.gz" $SUPPORT_DIR/
echo "Support package created: ${SUPPORT_DIR}.tar.gz"
```

### 2. 版本升级流程

#### 升级准备检查
```bash
#!/bin/bash
# pre-upgrade-check.sh

echo "Pre-upgrade compatibility check..."

# 检查当前版本
if [ -f "VERSION" ]; then
    CURRENT_VERSION=$(cat VERSION)
    echo "Current version: $CURRENT_VERSION"
else
    echo "Version file not found - assuming initial deployment"
fi

# 检查栈状态
echo "Checking current deployment status..."
./health-check.sh

# 创建备份
echo "Creating backup..."
./create-checkpoint.sh

echo "Pre-upgrade check completed"
echo "Proceed with upgrade only if all checks passed"
```

本故障排除指南涵盖了大部分常见问题和解决方案。如果遇到未列出的问题，请使用提供的诊断工具收集信息，并参考AWS服务文档或联系技术支持。