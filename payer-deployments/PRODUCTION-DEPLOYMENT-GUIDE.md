# 生产环境Payer部署标准流程

## 📋 概述

本文档基于测试部署指南，制定了标准化的生产环境Payer部署流程，确保每次部署的一致性和成功率。

**重要提醒**: 必须严格按照此流程执行，不可跳过任何步骤！

## 🎯 部署目标

- **目标**: 为新的Payer账户建立完整的AWS billing和管理基础设施
- **范围**: 7个核心模块的顺序部署
- **预期时间**: 3-4小时（包含等待时间）

## ⚠️ 关键前提条件

### 1. 账户类型要求
- ✅ **支持**: Organizations Master Account（直接部署）
- ✅ **支持**: 独立账户（自动创建Organizations后部署）
- ✅ **必须**: 账户具有管理员权限以创建Organizations
- ⚠️ **注意**: BillingConductor权限可能需要额外启用

### 2. 权限要求
- ✅ AdministratorAccess或等效权限
- ✅ BillingConductor完整权限
- ✅ Organizations管理权限

## 📊 部署前检查清单

### 步骤0: 环境准备和验证

在开始任何部署之前，**必须**完成以下检查：

```bash
# 切换到工作目录
cd /Users/di.miao/Work/payer-setup

# 1. 基础环境检查
echo "=== 基础环境检查 ==="
aws sts get-caller-identity
aws configure get region  # 必须返回 us-east-1

# 2. Organizations状态检查/创建 (自动处理)
echo "=== Organizations状态检查/创建 ==="
if aws organizations describe-organization >/dev/null 2>&1; then
    echo "✅ Organizations已存在"
    aws organizations describe-organization --query '{Id:Organization.Id,MasterAccountId:Organization.MasterAccountId}' --output table
else
    echo "⚠️ Organizations不存在，正在自动创建..."
    aws organizations create-organization --feature-set ALL
    echo "✅ Organizations创建完成！当前账户现在是Master Account"
    sleep 5  # 等待初始化完成
fi

# 3. BillingConductor权限检查
echo "=== BillingConductor权限检查 ==="
aws billingconductor list-billing-groups --region us-east-1

# 如果上述命令失败，STOP! 账户不是Payer账户
# 需要切换到Payer账户或联系AWS启用BillingConductor

# 4. 设置全局变量 (基于测试指南)
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"

# Organizations相关变量
export ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
export ORGANIZATION_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)

# 项目路径
export PROJECT_PATH="/Users/di.miao/Work/payer-setup/aws-payer-automation"
export DEPLOYMENT_PATH="/Users/di.miao/Work/payer-setup/payer-deployments"

echo "=== 环境变量验证 ==="
echo "ROOT_ID: $ROOT_ID"
echo "MASTER_ACCOUNT_ID: $MASTER_ACCOUNT_ID"
echo "ORGANIZATION_ID: $ORGANIZATION_ID"
echo "TIMESTAMP: $TIMESTAMP"

# 验证所有变量都已设置
if [ -z "$ROOT_ID" ] || [ -z "$MASTER_ACCOUNT_ID" ] || [ -z "$ORGANIZATION_ID" ]; then
    echo "❌ 关键变量未设置，请检查Organizations权限"
    exit 1
fi

echo "✅ 环境验证完成，可以开始部署"
```

### 步骤0.5: 创建变量文件

```bash
# 创建生产部署变量文件
cat > $DEPLOYMENT_PATH/config/production-variables.sh << EOF
#!/bin/bash
# 生产部署变量 - $(date)
export TIMESTAMP=$TIMESTAMP
export REGION="$REGION"
export STACK_PREFIX="$STACK_PREFIX"
export ROOT_ID="$ROOT_ID"
export MASTER_ACCOUNT_ID="$MASTER_ACCOUNT_ID"
export ORGANIZATION_ID="$ORGANIZATION_ID"
export PROJECT_PATH="$PROJECT_PATH"
export DEPLOYMENT_PATH="$DEPLOYMENT_PATH"

echo "✅ 生产环境变量已加载"
echo "Master Account: $MASTER_ACCOUNT_ID"
echo "Organization: $ORGANIZATION_ID"
echo "Timestamp: $TIMESTAMP"
EOF

chmod +x $DEPLOYMENT_PATH/config/production-variables.sh
echo "✅ 变量文件已创建: $DEPLOYMENT_PATH/config/production-variables.sh"
```

## 🚀 标准部署流程

### 模块部署顺序 (严格按照依赖关系)

```
步骤1: 模块1 (OU和SCP设置)
步骤2: 模块2 (BillingConductor账户和计费组)
步骤3: 模块3 (Pro forma CUR) + 模块4 (RISP CUR) [可并行]
步骤4: 模块5 (Athena环境设置)
步骤5: 模块6 (账户自动移动)
步骤6: 模块7 (CloudFront监控)
```

### 模块1: OU和SCP设置

```bash
# 加载环境变量
source $DEPLOYMENT_PATH/config/production-variables.sh

# 创建日志文件
LOG_FILE="$DEPLOYMENT_PATH/logs/production-module-01-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)

echo "开始模块1部署" | tee -a $LOG_FILE

# 验证模板存在
if [ ! -f "$PROJECT_PATH/templates/01-ou-scp/ou_scp.yaml" ]; then
    echo "⚠️ 模块1模板不存在，跳过OU/SCP设置" | tee -a $LOG_FILE
    echo "export MODULE1_SKIPPED=true" >> $DEPLOYMENT_PATH/config/production-variables.sh
else
    # 部署模块1
    aws cloudformation create-stack \
      --stack-name "${STACK_PREFIX}-ou-scp-${TIMESTAMP}" \
      --template-body file://$PROJECT_PATH/templates/01-ou-scp/ou_scp.yaml \
      --capabilities CAPABILITY_NAMED_IAM \
      --region $REGION \
      --tags Key=Module,Value=Module1 Key=Timestamp,Value=$TIMESTAMP | tee -a $LOG_FILE

    # 等待完成
    aws cloudformation wait stack-create-complete \
      --stack-name "${STACK_PREFIX}-ou-scp-${TIMESTAMP}" \
      --region $REGION

    echo "✅ 模块1部署完成" | tee -a $LOG_FILE
fi
```

### 模块2: BillingConductor (关键模块)

```bash
echo "开始模块2部署 - BillingConductor" | tee -a $LOG_FILE

# 验证BillingConductor权限 (再次确认)
if ! aws billingconductor list-billing-groups --region us-east-1 >/dev/null 2>&1; then
    echo "❌ BillingConductor权限不足，无法部署模块2" | tee -a $LOG_FILE
    exit 1
fi

# 使用修复后的模板部署
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-billing-conductor-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/02-billing-conductor/billing_conductor.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=Module,Value=Module2 Key=Timestamp,Value=$TIMESTAMP | tee -a $LOG_FILE

echo "⏳ 模块2部署中 - 预计需要30-45分钟（包含账户创建和CB family集成）" | tee -a $LOG_FILE

# 监控部署进度
while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-billing-conductor-${TIMESTAMP}" \
    --region $REGION \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "PENDING")
  
  echo "$(date): 模块2状态: $STATUS" | tee -a $LOG_FILE
  
  case $STATUS in
    "CREATE_COMPLETE")
      echo "✅ 模块2部署成功!" | tee -a $LOG_FILE
      break
      ;;
    "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"ROLLBACK_FAILED")
      echo "❌ 模块2部署失败: $STATUS" | tee -a $LOG_FILE
      # 获取失败详情
      aws cloudformation describe-stack-events \
        --stack-name "${STACK_PREFIX}-billing-conductor-${TIMESTAMP}" \
        --region $REGION \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
        --output table | tee -a $LOG_FILE
      exit 1
      ;;
    "CREATE_IN_PROGRESS")
      echo "⏳ 继续等待..." | tee -a $LOG_FILE
      sleep 120  # 每2分钟检查一次
      ;;
    *)
      echo "⚠️ 未知状态: $STATUS" | tee -a $LOG_FILE
      sleep 60
      ;;
  esac
done

# 获取输出变量
NEW_ACCOUNT_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_PREFIX}-billing-conductor-${TIMESTAMP}" \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`NewAccountId`].OutputValue' \
  --output text)

BILLING_GROUP_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_PREFIX}-billing-conductor-${TIMESTAMP}" \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' \
  --output text)

# 保存变量
echo "export NEW_ACCOUNT_ID=$NEW_ACCOUNT_ID" >> $DEPLOYMENT_PATH/config/production-variables.sh
echo "export BILLING_GROUP_ARN='$BILLING_GROUP_ARN'" >> $DEPLOYMENT_PATH/config/production-variables.sh
echo "export MODULE2_STACK_NAME='${STACK_PREFIX}-billing-conductor-${TIMESTAMP}'" >> $DEPLOYMENT_PATH/config/production-variables.sh

echo "✅ 模块2完成 - 新账户: $NEW_ACCOUNT_ID" | tee -a $LOG_FILE
```

### 模块3和4: CUR设置 (可并行)

```bash
echo "开始模块3和4并行部署 - CUR设置" | tee -a $LOG_FILE

# 模块3: Pro forma CUR
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-cur-proforma-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/03-cur-proforma/cur_proforma.yaml \
  --capabilities CAPABILITY_IAM \
  --region $REGION \
  --parameter-overrides NewAccountId=$NEW_ACCOUNT_ID \
  --tags Key=Module,Value=Module3 Key=Timestamp,Value=$TIMESTAMP &

# 模块4: RISP CUR
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-cur-risp-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/04-cur-risp/cur_risp.yaml \
  --capabilities CAPABILITY_IAM \
  --region $REGION \
  --parameter-overrides NewAccountId=$NEW_ACCOUNT_ID \
  --tags Key=Module,Value=Module4 Key=Timestamp,Value=$TIMESTAMP &

# 等待两个栈完成
wait

echo "✅ 模块3和4部署完成" | tee -a $LOG_FILE
```

### 模块5: Athena环境 ⚠️ 使用修复版本

```bash
echo "开始模块5部署 - Athena环境 (使用v1修复版本)" | tee -a $LOG_FILE

# 使用v1版本的修复模板 (推荐方式)
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-athena-setup-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/current/05-athena-setup/athena_setup.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region $REGION \
  --parameters \
    ParameterKey=ProformaBucketName,ParameterValue=bip-cur-${MASTER_ACCOUNT_ID} \
    ParameterKey=RISPBucketName,ParameterValue=bip-risp-cur-${MASTER_ACCOUNT_ID} \
    ParameterKey=ProformaReportName,ParameterValue=${MASTER_ACCOUNT_ID} \
    ParameterKey=RISPReportName,ParameterValue=risp-${MASTER_ACCOUNT_ID} \
  --tags Key=Module,Value=Module5 Key=Version,Value=v1 Key=Timestamp,Value=$TIMESTAMP

# 或使用版本管理脚本 (推荐)
# ./deployment-scripts/version-management.sh deploy 05-athena-setup v1 "${STACK_PREFIX}-athena-setup-${TIMESTAMP}"

aws cloudformation wait stack-create-complete \
  --stack-name "${STACK_PREFIX}-athena-setup-${TIMESTAMP}" \
  --region $REGION

echo "✅ 模块5部署完成 (使用v1修复版本)" | tee -a $LOG_FILE
```

### 模块6和7: 管理功能 ⚠️ Module 6使用修复版本

```bash
echo "开始模块6和7部署 - 管理功能" | tee -a $LOG_FILE

# 模块6: 账户自动移动 (使用v1修复版本)
if [ "$MODULE1_SKIPPED" != "true" ]; then
    # 使用v1版本的修复模板 (推荐方式)
    aws cloudformation create-stack \
      --stack-name "${STACK_PREFIX}-account-management-${TIMESTAMP}" \
      --template-body file://$PROJECT_PATH/templates/current/06-account-auto-management/account_auto_move.yaml \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      --region $REGION \
      --parameters ParameterKey=NormalOUId,ParameterValue=$NORMAL_OU_ID \
      --tags Key=Module,Value=Module6 Key=Version,Value=v1 Key=Timestamp,Value=$TIMESTAMP
      
    # 或使用版本管理脚本 (推荐)
    # ./deployment-scripts/version-management.sh deploy 06-account-auto-management v1 "${STACK_PREFIX}-account-management-${TIMESTAMP}"
fi

# 模块7: CloudFront监控 (v1版本稳定)
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-cloudfront-monitoring-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/current/07-cloudfront-monitoring/cloudfront_monitoring.yaml \
  --capabilities CAPABILITY_IAM \
  --region $REGION \
  --tags Key=Module,Value=Module7 Key=Version,Value=v1 Key=Timestamp,Value=$TIMESTAMP

echo "✅ 所有模块部署完成! (使用v1稳定版本)" | tee -a $LOG_FILE
```

## 🔍 部署后验证

```bash
echo "=== 部署验证 ===" | tee -a $LOG_FILE

# 1. 验证新账户
if [ -n "$NEW_ACCOUNT_ID" ]; then
    aws organizations describe-account --account-id $NEW_ACCOUNT_ID | tee -a $LOG_FILE
fi

# 2. 验证BillingGroup
if [ -n "$BILLING_GROUP_ARN" ]; then
    aws billingconductor get-billing-group --arn "$BILLING_GROUP_ARN" --region us-east-1 | tee -a $LOG_FILE
fi

# 3. 列出所有创建的栈
echo "创建的CloudFormation栈:" | tee -a $LOG_FILE
aws cloudformation list-stacks --region $REGION \
  --query "StackSummaries[?contains(StackName, '$STACK_PREFIX') && StackStatus != 'DELETE_COMPLETE'].{Name:StackName,Status:StackStatus}" \
  --output table | tee -a $LOG_FILE
```

## ❌ 常见错误和解决方案

### 错误1: Organizations权限不足
**症状**: `AWSOrganizationsNotInUseException`  
**原因**: 账户不是Organizations成员  
**解决**: 确认使用正确的Master Account凭证

### 错误2: BillingConductor访问被拒绝
**症状**: `AccessDeniedException` for BillingConductor  
**原因**: 账户不是Payer账户  
**解决**: 确认账户已启用BillingConductor服务

### 错误3: Lambda超时设置错误
**症状**: `Member must have value less than or equal to 900`  
**原因**: Lambda超时时间超过15分钟限制  
**解决**: 已在模板中修复为900秒

### 错误4: 跳过前置条件检查
**症状**: 部署中途失败  
**原因**: 没有验证环境要求  
**解决**: 严格执行步骤0的所有检查

## 🔄 **版本管理系统** (2025-07-24)

基于Elite-new11部署经验建立的版本管理系统，确保使用稳定的模板版本：

### 🎯 推荐部署方式

```bash
# 使用版本管理脚本进行完整部署 (最推荐)
export MASTER_ACCOUNT_ID="你的主账户ID"
export NORMAL_OU_ID="你的Normal OU ID"
export PAYER_NAME="你的Payer名称"

cd /Users/di.miao/Work/payer-setup/aws-payer-automation
./deployment-scripts/version-management.sh deploy-all v1 $PAYER_NAME

# 查看可用版本
./deployment-scripts/version-management.sh list-versions

# 查看v1版本详情
./deployment-scripts/version-management.sh version-info v1
```

### 🔧 版本对照

| 版本 | 状态 | 描述 | 推荐使用 |
|------|------|------|----------|
| v0 | deprecated | 原始版本，存在已知问题 | ❌ 不推荐 |
| v1 | stable | Elite-new11验证通过的稳定版本 | ✅ **推荐** |
| current | symlink | 自动指向推荐的稳定版本(v1) | ✅ **推荐** |

## 🚨 **Elite-new11修复经验** (已集成到v1版本)

基于Elite-new11实际部署过程中发现的问题，以下修复已集成到v1版本：

### 🔧 问题1: Module 6 Lambda函数名长度超限
**症状**: 
```
Value 'payer-Elite-new11-account-management-1753341764-CloudTrailManager' at 'functionName' failed to satisfy constraint: Member must have length less than or equal to 64
```
**原因**: 使用`!Sub "${AWS::StackName}-CloudTrailManager"`导致函数名超过64字符限制
**解决方案**: 创建修复模板`account_auto_move_fixed_v2.yaml`
```yaml
# 原有问题代码
FunctionName: !Sub "${AWS::StackName}-CloudTrailManager"

# 修复后代码  
FunctionName: !Sub 
  - "Elite-${ShortName}-CTManager"
  - ShortName: !Select [1, !Split ["-", !Ref "AWS::StackName"]]
```
**状态**: ✅ 已修复并验证

### 🔧 问题2: Module 5 Lambda代码过长导致zip错误
**症状**: 
```
Could not unzip uploaded file. Please check your file, then try to upload again.
```
**原因**: 内联Lambda代码28,869字符，超过CloudFormation ZipFile限制（~4KB）
**解决方案**: 创建简化模板`athena_setup_fixed.yaml`
- 移除复杂的S3通知、状态表等高级功能
- 保留核心功能：Glue数据库、Crawlers、IAM角色
- 代码简化到可管理的大小
**状态**: ✅ 已修复并验证

### 📝 修复后的模板文件列表
```
修复文件:
├── templates/06-account-auto-management/
│   └── account_auto_move_fixed_v2.yaml     # Module 6修复版
└── templates/05-athena-setup/
    └── athena_setup_fixed.yaml             # Module 5修复版
```

### 🎯 部署命令更新
使用修复后的模板进行部署：

**Module 5 (Athena Setup)**:
```bash
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-athena-setup-fixed-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/05-athena-setup/athena_setup_fixed.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameters \
    ParameterKey=ProformaBucketName,ParameterValue=bip-cur-${MASTER_ACCOUNT_ID} \
    ParameterKey=RISPBucketName,ParameterValue=bip-risp-cur-${MASTER_ACCOUNT_ID} \
    ParameterKey=ProformaReportName,ParameterValue=${MASTER_ACCOUNT_ID} \
    ParameterKey=RISPReportName,ParameterValue=risp-${MASTER_ACCOUNT_ID}
```

**Module 6 (Account Management)**:
```bash
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-account-management-fixed-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/06-account-auto-management/account_auto_move_fixed_v2.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameters ParameterKey=NormalOUId,ParameterValue=$NORMAL_OU_ID
```

### ⚠️ 重要提醒 (v1版本已修复)
1. **使用v1稳定版本**: 推荐使用`templates/current/`或`templates/versions/v1/`
2. **避免v0版本**: v0版本存在已知问题，标记为deprecated
3. **版本管理脚本**: 推荐使用`./deployment-scripts/version-management.sh`进行部署
4. **完整性验证**: 部署完成后验证所有资源创建成功
5. **向后兼容**: 现有脚本仍然可用，会自动使用v1版本

### 📊 Elite-new11部署成功确认 (v1版本验证)
- ✅ Module 2: BillingConductor + 新账户 (163814384698)
- ✅ Module 5: Athena环境 (v1版本，已修复Lambda代码过长问题)
- ✅ Module 6: 账户自动管理 (v1版本，已修复函数名长度问题)
- ✅ BillingGroup: "Bills" 正确创建并关联
- ✅ Glue Crawlers: 已创建并准备处理CUR数据
- ✅ 版本管理: 所有修复已集成到v1稳定版本

## 🧹 清理流程

如需清理部署资源（测试或失败情况）：

```bash
# 按相反顺序删除栈
STACKS=(
    "${STACK_PREFIX}-cloudfront-monitoring-${TIMESTAMP}"
    "${STACK_PREFIX}-account-management-${TIMESTAMP}"
    "${STACK_PREFIX}-athena-setup-${TIMESTAMP}"
    "${STACK_PREFIX}-cur-risp-${TIMESTAMP}"
    "${STACK_PREFIX}-cur-proforma-${TIMESTAMP}"
    "${STACK_PREFIX}-billing-conductor-${TIMESTAMP}"
    "${STACK_PREFIX}-ou-scp-${TIMESTAMP}"
)

for stack in "${STACKS[@]}"; do
    echo "删除栈: $stack"
    aws cloudformation delete-stack --stack-name "$stack" --region $REGION
done
```

## 📝 部署记录

每次成功部署后，记录以下信息：

- **部署时间**: $(date)
- **Payer账户**: $MASTER_ACCOUNT_ID
- **新Bills账户**: $NEW_ACCOUNT_ID
- **BillingGroup ARN**: $BILLING_GROUP_ARN
- **部署日志**: $LOG_FILE

---

**重要提醒**: 本流程基于测试验证，必须严格按照顺序执行。任何跳过或修改都可能导致部署失败。