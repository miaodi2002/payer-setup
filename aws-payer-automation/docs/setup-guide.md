# AWS Payer自动化初始化 - 详细设置指南

## 概述

本指南详细介绍AWS Payer自动化初始化项目的完整设置流程，包括前置条件检查、环境准备、逐步部署和验证。

## 前置条件检查

### 1. AWS账户要求

#### 账户类型
- **主账户**: 必须是AWS Organizations的管理账户
- **权限**: 需要完整的管理员权限
- **区域**: 主要操作在us-east-1（CUR要求）

#### 账户状态验证
```bash
# 检查当前账户身份
aws sts get-caller-identity

# 检查Organizations状态
aws organizations describe-organization

# 检查是否为管理账户
aws organizations describe-account --account-id $(aws sts get-caller-identity --query Account --output text)
```

### 2. IAM权限要求

#### 必需权限策略
创建具有以下权限的IAM用户或角色：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "organizations:*",
                "billingconductor:*",
                "cur:*",
                "s3:*",
                "lambda:*",
                "glue:*",
                "cloudformation:*",
                "logs:*",
                "kms:*",
                "cloudtrail:*",
                "events:*",
                "athena:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:GetRole",
                "iam:UpdateRole",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:GetRolePolicy",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:ListRolePolicies",
                "iam:ListAttachedRolePolicies",
                "iam:PassRole",
                "iam:TagRole",
                "iam:UntagRole",
                "iam:ListRoles"
            ],
            "Resource": "*"
        }
    ]
}
```

**权限说明**：
- `organizations:*`: AWS Organizations完整管理权限
- `billingconductor:*`: BillingConductor服务权限（Module 2）
- `cur:*`: Cost and Usage Reports权限（Module 3, 4）
- `s3:*`: S3完整权限（存储桶和CUR数据）
- `lambda:*`: Lambda函数管理权限
- `glue:*`: AWS Glue数据目录权限（Module 5）
- `cloudformation:*`: CloudFormation完整权限
- `logs:*`: CloudWatch Logs权限
- `kms:*`: KMS加密权限
- `cloudtrail:*`: CloudTrail管理权限（Module 6）
- `events:*`: EventBridge权限（Module 6）
- `athena:*`: Athena查询引擎权限（Module 5）
- **IAM权限限制**: 只允许角色管理相关权限，不包含用户和策略管理

#### 权限验证脚本
```bash
#!/bin/bash
# check-permissions.sh

echo "Checking required permissions..."

# Organizations权限
if aws organizations describe-organization &> /dev/null; then
    echo "✓ Organizations access confirmed"
else
    echo "✗ Organizations access denied"
    exit 1
fi

# CloudFormation权限
if aws cloudformation list-stacks &> /dev/null; then
    echo "✓ CloudFormation access confirmed"
else
    echo "✗ CloudFormation access denied"
    exit 1
fi

# S3权限
if aws s3 ls &> /dev/null; then
    echo "✓ S3 access confirmed"
else
    echo "✗ S3 access denied"
    exit 1
fi

# Lambda权限
if aws lambda list-functions &> /dev/null; then
    echo "✓ Lambda access confirmed"
else
    echo "✗ Lambda access denied"
    exit 1
fi

# CloudTrail权限（Module 6）
if aws cloudtrail describe-trails &> /dev/null; then
    echo "✓ CloudTrail access confirmed"
else
    echo "✗ CloudTrail access denied"
    exit 1
fi

# EventBridge权限（Module 6）
if aws events list-rules &> /dev/null; then
    echo "✓ EventBridge access confirmed"
else
    echo "✗ EventBridge access denied"
    exit 1
fi

# Glue权限（Module 5）
if aws glue get-databases &> /dev/null; then
    echo "✓ Glue access confirmed"
else
    echo "✗ Glue access denied"
    exit 1
fi

# Athena权限（Module 5）
if aws athena list-work-groups &> /dev/null; then
    echo "✓ Athena access confirmed"
else
    echo "✗ Athena access denied"
    exit 1
fi

# BillingConductor权限（Module 2）
if aws billingconductor list-billing-groups --region us-east-1 &> /dev/null; then
    echo "✓ BillingConductor access confirmed"
else
    echo "⚠ BillingConductor access limited (may be expected)"
fi

# CUR权限（Module 3, 4）
if aws cur describe-report-definitions --region us-east-1 &> /dev/null; then
    echo "✓ CUR access confirmed"
else
    echo "⚠ CUR access limited (may be expected)"
fi

# IAM权限验证
if aws iam list-roles --max-items 1 &> /dev/null; then
    echo "✓ IAM role management access confirmed"
else
    echo "✗ IAM role management access denied"
    exit 1
fi

echo "Permission check completed successfully"
echo ""
echo "All required permissions are available for AWS Payer automation deployment."
```

### 3. AWS服务启用状态

#### Organizations设置
```bash
# 检查Organizations功能
aws organizations describe-organization

# 检查SCP功能状态
aws organizations describe-organization --query 'Organization.AvailablePolicyTypes'

# 如果SCP未启用，需要启用
aws organizations enable-policy-type --root-id r-xxxx --policy-type SERVICE_CONTROL_POLICY
```

#### 获取Root ID
```bash
# 获取Organizations Root ID（Module 1需要）
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Root ID: $ROOT_ID"

# 验证Root ID有效性
aws organizations describe-organizational-unit --organizational-unit-id $ROOT_ID
```

## 环境准备

### 1. 工具安装

#### AWS CLI
```bash
# 安装AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# 验证安装
aws --version
```

#### 可选工具
```bash
# YAML语法检查工具
pip install yamllint

# JSON处理工具
sudo apt-get install jq  # Ubuntu/Debian
brew install jq          # macOS
```

### 2. 项目设置

#### 下载项目
```bash
git clone <repository-url>
cd aws-payer-automation

# 验证项目结构
ls -la
tree .  # 如果有tree命令
```

#### 脚本权限设置
```bash
# 使脚本可执行
chmod +x scripts/*.sh

# 验证脚本权限
ls -la scripts/
```

### 3. 配置验证

#### 模板语法验证
```bash
# 运行完整验证
./scripts/validate.sh

# 手动验证单个模板
aws cloudformation validate-template --template-body file://templates/01-ou-scp/auto_SCP_1.yaml
```

## 分步部署指南

### Step 1: 部署OU和SCP（Module 1）

#### 1.1 准备参数
```bash
# 获取必需的Root ID
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Root ID: $ROOT_ID"

# 验证参数有效性
if [ -z "$ROOT_ID" ] || [ "$ROOT_ID" = "None" ]; then
    echo "Error: Cannot retrieve valid Root ID"
    exit 1
fi
```

#### 1.2 部署执行
```bash
# 部署Module 1
./scripts/deploy-single.sh 1 --root-id $ROOT_ID

# 或者手动部署
aws cloudformation create-stack \
    --stack-name payer-ou-scp-$(date +%s) \
    --template-body file://templates/01-ou-scp/auto_SCP_1.yaml \
    --parameters ParameterKey=RootId,ParameterValue=$ROOT_ID \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1
```

#### 1.3 验证结果
```bash
# 检查栈状态
aws cloudformation describe-stacks --stack-name payer-ou-scp-*

# 验证OU创建
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID

# 验证SCP策略
aws organizations list-policies --filter SERVICE_CONTROL_POLICY
```

### Step 2: 部署BillingConductor（Module 2）

#### 2.1 前置检查
```bash
# 检查BillingConductor可用性
aws billingconductor list-billing-groups --region us-east-1

# 检查账户创建权限
aws organizations describe-create-account-status --create-account-request-id test 2>/dev/null || echo "Account creation permissions available"
```

#### 2.2 部署执行
```bash
# 部署Module 2
./scripts/deploy-single.sh 2

# 监控账户创建进度（可能需要30分钟）
watch -n 30 "aws cloudformation describe-stack-events --stack-name payer-billing-conductor-* --max-items 5"
```

#### 2.3 获取输出
```bash
# 获取新账户信息
STACK_NAME=$(aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, `payer-billing-conductor-`)].StackName' --output text)

NEW_ACCOUNT_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`NewAccountId`].OutputValue' --output text)

BILLING_GROUP_ARN=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' --output text)

echo "New Account ID: $NEW_ACCOUNT_ID"
echo "BillingGroup ARN: $BILLING_GROUP_ARN"
```

### Step 3: 部署Pro forma CUR（Module 3）

#### 3.1 参数验证
```bash
# 验证BillingGroup ARN
if [ -z "$BILLING_GROUP_ARN" ]; then
    echo "Error: BillingGroup ARN is required"
    echo "Get it from Module 2 stack outputs"
    exit 1
fi

# 验证ARN格式
if [[ ! $BILLING_GROUP_ARN =~ ^arn:aws:billingconductor::.* ]]; then
    echo "Error: Invalid BillingGroup ARN format"
    exit 1
fi
```

#### 3.2 部署执行
```bash
# 部署Module 3
./scripts/deploy-single.sh 3 --billing-group-arn $BILLING_GROUP_ARN
```

#### 3.3 验证CUR设置
```bash
# 检查CUR报告
aws cur describe-report-definitions --region us-east-1

# 检查S3存储桶
aws s3 ls | grep bip-cur-
```

### Step 4: 部署RISP CUR（Module 4）

#### 4.1 部署执行
```bash
# 部署Module 4（无需参数）
./scripts/deploy-single.sh 4
```

#### 4.2 验证RISP CUR
```bash
# 检查RISP CUR报告
aws cur describe-report-definitions --region us-east-1 | grep risp

# 检查RISP S3存储桶
aws s3 ls | grep bip-risp-cur-
```

### Step 5: 部署Athena环境（Module 5）

#### 5.1 获取前置参数
```bash
# 获取Module 3和4的输出参数
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

echo "Pro forma Bucket: $PROFORMA_BUCKET"
echo "RISP Bucket: $RISP_BUCKET"
echo "Pro forma Report: $PROFORMA_REPORT"
echo "RISP Report: $RISP_REPORT"
```

#### 5.2 部署执行
```bash
# 部署Module 5
./scripts/deploy-single.sh 5 \
  --proforma-bucket $PROFORMA_BUCKET \
  --risp-bucket $RISP_BUCKET \
  --proforma-report $PROFORMA_REPORT \
  --risp-report $RISP_REPORT
```

#### 5.3 验证Athena设置
```bash
# 检查Glue数据库
aws glue get-databases

# 检查Glue爬虫
aws glue get-crawlers

# 检查Athena工作组
aws athena list-work-groups
```

### Step 6: 部署账户自动移动（Module 6）

#### 6.1 获取Normal OU ID
```bash
# 获取Module 1创建的Normal OU ID
NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name payer-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text)

echo "Normal OU ID: $NORMAL_OU_ID"

# 验证OU存在
aws organizations describe-organizational-unit --organizational-unit-id $NORMAL_OU_ID
```

#### 6.2 部署执行
```bash
# 智能模式部署（推荐 - 自动检测CloudTrail基础设施）
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID

# 或者明确指定模式
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID --cloudtrail-mode auto

# 强制创建新CloudTrail
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID --cloudtrail-mode true

# 跳过CloudTrail创建
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID --cloudtrail-mode false
```

#### 6.3 验证自动移动设置
```bash
# 检查EventBridge规则
aws events list-rules --name-prefix CreateAccountResult
aws events list-rules --name-prefix AcceptHandshake

# 检查Lambda函数
aws lambda get-function --function-name AccountAutoMover

# 检查CloudTrail状态
aws cloudtrail describe-trails
aws cloudtrail get-trail-status --name bip-organizations-management-trail

# 验证CloudTrail事件选择器
aws cloudtrail get-event-selectors --trail-name bip-organizations-management-trail
```

## 验证和测试

### 1. 完整性检查

#### 栈状态验证
```bash
# 检查所有相关栈
./scripts/cleanup.sh --list

# 检查栈输出
for stack in $(aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, `payer-`)].StackName' --output text); do
    echo "=== $stack ==="
    aws cloudformation describe-stacks --stack-name $stack --query 'Stacks[0].Outputs'
done
```

#### 资源验证
```bash
# 验证OU结构
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID

# 验证账户
aws organizations list-accounts

# 验证BillingGroup
aws billingconductor list-billing-groups --region us-east-1

# 验证CUR报告
aws cur describe-report-definitions --region us-east-1

# 验证Glue数据库和爬虫（Module 5）
aws glue get-databases
aws glue get-crawlers

# 验证EventBridge规则（Module 6）
aws events list-rules --name-prefix CreateAccountResult
aws events list-rules --name-prefix AcceptHandshake

# 验证Lambda函数（Module 6）
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `AccountAutoMover`)].FunctionName'

# 验证CloudTrail（Module 6）
aws cloudtrail describe-trails
```

### 2. 功能测试

#### SCP策略测试
```bash
# 检查SCP附加状态
for ou in $(aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID --query 'OrganizationalUnits[].Id' --output text); do
    echo "OU: $ou"
    aws organizations list-policies-for-target --target-id $ou --filter SERVICE_CONTROL_POLICY
done
```

#### 新账户访问测试
```bash
# 尝试切换到新账户（如果有cross-account角色）
aws sts assume-role --role-arn arn:aws:iam::$NEW_ACCOUNT_ID:role/OrganizationAccountAccessRole --role-session-name test-session
```

## 故障排除

### 常见问题和解决方案

#### 1. 账户创建失败
```bash
# 检查创建状态
aws organizations list-create-account-status

# 查看失败原因
aws organizations describe-create-account-status --create-account-request-id <request-id>
```

#### 2. SCP附加失败
```bash
# 检查SCP功能状态
aws organizations describe-organization --query 'Organization.AvailablePolicyTypes'

# 手动启用SCP
aws organizations enable-policy-type --root-id $ROOT_ID --policy-type SERVICE_CONTROL_POLICY
```

#### 3. CUR创建失败
```bash
# 检查区域设置
echo $AWS_DEFAULT_REGION  # 应该是us-east-1

# 检查S3权限
aws s3 ls
aws s3api get-bucket-location --bucket <bucket-name>
```

#### 4. CloudFormation栈失败
```bash
# 查看栈事件
aws cloudformation describe-stack-events --stack-name <stack-name>

# 查看失败资源
aws cloudformation list-stack-resources --stack-name <stack-name> --stack-resource-status FAILED
```

### 清理和重试

#### 部分清理
```bash
# 删除失败的栈
./scripts/cleanup.sh --delete-stack <stack-name>

# 查看清理进度
watch -n 10 "aws cloudformation describe-stacks --stack-name <stack-name>"
```

#### 完全重置
```bash
# 谨慎使用：删除所有相关栈
./scripts/cleanup.sh --delete-all --dry-run  # 先查看会删除什么
./scripts/cleanup.sh --delete-all             # 确认后执行
```

## 部署后配置

### 1. 账户设置

#### 新账户初始配置
```bash
# 为新账户设置别名
aws iam create-account-alias --account-alias my-company-bills

# 创建初始IAM用户（如需要）
aws iam create-user --user-name bills-admin
```

### 2. CUR数据访问

#### Athena设置
```bash
# 创建Athena数据库（如果需要）
aws athena start-query-execution \
    --query-string "CREATE DATABASE IF NOT EXISTS cur_database" \
    --result-configuration OutputLocation=s3://my-athena-results/
```

#### 数据验证（24小时后）
```bash
# 检查S3中的CUR数据
aws s3 ls s3://bip-cur-$ACCOUNT_ID/ --recursive

# 检查RISP数据
aws s3 ls s3://bip-risp-cur-$ACCOUNT_ID/ --recursive
```

## 监控和维护

### 日常监控

#### 栈健康检查
```bash
# 创建监控脚本
cat > monitor-stacks.sh << 'EOF'
#!/bin/bash
for stack in $(aws cloudformation list-stacks --query 'StackSummaries[?starts_with(StackName, `payer-`)].StackName' --output text); do
    status=$(aws cloudformation describe-stacks --stack-name $stack --query 'Stacks[0].StackStatus' --output text)
    echo "$stack: $status"
done
EOF

chmod +x monitor-stacks.sh
```

#### CUR数据监控
```bash
# 检查CUR更新状态
aws cur describe-report-definitions --region us-east-1 --query 'ReportDefinitions[].{Name:ReportName,LastUpdate:LastDelivery}'
```

### 定期维护

#### 1. 安全审查
- 定期检查SCP策略有效性
- 审查IAM权限
- 验证S3存储桶安全设置

#### 2. 成本优化
- 监控S3存储成本
- 检查不必要的资源
- 优化CUR报告频率

#### 3. 备份策略
- 导出CloudFormation模板
- 备份重要配置
- 记录部署参数

本设置指南提供了完整的部署流程和故障排除方法。如需更多帮助，请参考项目的其他文档或联系技术支持团队。