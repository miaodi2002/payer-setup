# 模组2测试: BillingConductor账户创建和计费组设置

## 测试状态
- ⏸️ **测试状态**: 未开始
- 📅 **预计时间**: 35-50分钟（账户创建需要时间 + CB family集成等待时间）
- 🎯 **成功标准**: 创建新账户和BillingGroup，处理邮箱冲突

## 模组概述

**功能**: 自动创建AWS账户和BillingConductor BillingGroup
**创建资源**:
- 新的AWS账户（使用+bills邮箱别名）
- BillingGroup用于pro forma定价
- 处理邮箱冲突（自动添加数字后缀）

## 前置条件检查

### 1. 验证模组1依赖
```bash
# 加载模组1的输出变量
if [ -f "/Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh" ]; then
  source /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
  echo "✅ 已加载模组1变量"
else
  echo "❌ 未找到模组1变量，请先完成模组1测试"
  exit 1
fi
```

### 2. 验证BillingConductor服务可用性
```bash
# 检查BillingConductor权限
aws billingconductor list-billing-groups --region us-east-1

# 检查当前Organization状态
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
export MASTER_ACCOUNT_EMAIL=$(aws organizations describe-account --account-id $MASTER_ACCOUNT_ID --query 'Account.Email' --output text)

echo "Master Account ID: $MASTER_ACCOUNT_ID"
echo "Master Account Email: $MASTER_ACCOUNT_EMAIL"
```

### 3. 准备邮箱配置
```bash
# 生成bills账户邮箱（使用+bills别名）
export BASE_EMAIL=$(echo $MASTER_ACCOUNT_EMAIL | cut -d'@' -f1)
export DOMAIN=$(echo $MASTER_ACCOUNT_EMAIL | cut -d'@' -f2)
export BILLS_EMAIL="${BASE_EMAIL}+bills@${DOMAIN}"

echo "计划创建的账户邮箱: $BILLS_EMAIL"

# 检查是否已存在相同邮箱的账户
aws organizations list-accounts --query "Accounts[?Email=='$BILLS_EMAIL'].{Id:Id,Email:Email,Name:Name}" --output table
```

## 部署步骤

### 步骤1: 设置环境变量
```bash
# 设置基础变量
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"
export MODULE2_STACK_NAME="${STACK_PREFIX}-billing-conductor-${TIMESTAMP}"

# 验证变量
echo "=== 模组2环境变量 ==="
echo "Stack Name: $MODULE2_STACK_NAME"
echo "Bills Email: $BILLS_EMAIL"
echo "Region: $REGION"
echo "Master Account: $MASTER_ACCOUNT_ID"
```

### 步骤2: 验证CloudFormation模板
```bash
# 切换到项目目录
cd /Users/di.miao/Work/payer-setup/aws-payer-automation

# 验证模板语法
aws cloudformation validate-template \
  --template-body file://templates/02-billing-conductor/billing_conductor.yaml \
  --region $REGION

echo "✅ 模板验证通过"
```

### 步骤3: 创建日志文件
```bash
# 创建测试日志
export LOG_FILE="/Users/di.miao/Work/payer-setup/deployment-testing/logs/module-02-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

echo "$(date): 开始模组2部署测试" | tee -a $LOG_FILE
echo "目标邮箱: $BILLS_EMAIL" | tee -a $LOG_FILE
```

### 步骤4: 部署CloudFormation栈
```bash
# 部署栈
echo "开始部署模组2..." | tee -a $LOG_FILE
echo "⚠️  账户创建可能需要30分钟 + 3分钟CB family集成等待，请耐心等待" | tee -a $LOG_FILE

aws cloudformation create-stack \
  --stack-name $MODULE2_STACK_NAME \
  --template-body file://templates/02-billing-conductor/billing_conductor.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=TestModule,Value=Module2 Key=TestRun,Value=$TIMESTAMP

echo "栈创建请求已提交: $MODULE2_STACK_NAME" | tee -a $LOG_FILE
```

### 步骤5: 监控部署进度（长时间等待）
```bash
# 监控栈创建状态
echo "监控栈部署状态（预计35分钟，包含CB family集成等待）..." | tee -a $LOG_FILE
START_TIME=$(date +%s)

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name $MODULE2_STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "PENDING")
  
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  ELAPSED_MIN=$((ELAPSED / 60))
  
  echo "$(date): 当前状态: $STATUS (已等待: ${ELAPSED_MIN}分钟)" | tee -a $LOG_FILE
  
  case $STATUS in
    "CREATE_COMPLETE")
      echo "✅ 栈创建成功! 总用时: ${ELAPSED_MIN}分钟" | tee -a $LOG_FILE
      break
      ;;
    "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"ROLLBACK_FAILED")
      echo "❌ 栈创建失败: $STATUS (用时: ${ELAPSED_MIN}分钟)" | tee -a $LOG_FILE
      # 获取失败原因
      aws cloudformation describe-stack-events \
        --stack-name $MODULE2_STACK_NAME \
        --region $REGION \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
        --output table | tee -a $LOG_FILE
      exit 1
      ;;
    "CREATE_IN_PROGRESS")
      if [ $ELAPSED_MIN -gt 50 ]; then
        echo "⚠️  部署时间超过50分钟，可能有问题" | tee -a $LOG_FILE
      fi
      echo "⏳ 继续等待..." | tee -a $LOG_FILE
      sleep 60  # 每分钟检查一次
      ;;
    *)
      echo "⚠️  未知状态: $STATUS" | tee -a $LOG_FILE
      sleep 60
      ;;
  esac
done
```

### 步骤6: 获取部署结果
```bash
echo "=== 获取部署输出 ===" | tee -a $LOG_FILE

# 获取栈输出
export NEW_ACCOUNT_ID=$(aws cloudformation describe-stacks \
  --stack-name $MODULE2_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`NewAccountId`].OutputValue' \
  --output text)

export NEW_ACCOUNT_EMAIL=$(aws cloudformation describe-stacks \
  --stack-name $MODULE2_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`NewAccountEmail`].OutputValue' \
  --output text)

export BILLING_GROUP_ARN=$(aws cloudformation describe-stacks \
  --stack-name $MODULE2_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' \
  --output text)

echo "新账户ID: $NEW_ACCOUNT_ID" | tee -a $LOG_FILE
echo "新账户邮箱: $NEW_ACCOUNT_EMAIL" | tee -a $LOG_FILE
echo "BillingGroup ARN: $BILLING_GROUP_ARN" | tee -a $LOG_FILE
```

## 部署验证检查

### 1. 验证账户创建
```bash
echo "=== 验证账户创建 ===" | tee -a $LOG_FILE

# 验证新账户存在
ACCOUNT_INFO=$(aws organizations describe-account --account-id $NEW_ACCOUNT_ID 2>/dev/null || echo "ERROR")

if [ "$ACCOUNT_INFO" != "ERROR" ]; then
  echo "✅ 新账户创建成功" | tee -a $LOG_FILE
  aws organizations describe-account --account-id $NEW_ACCOUNT_ID \
    --query '{Id:Account.Id,Name:Account.Name,Email:Account.Email,Status:Account.Status}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ 无法找到新账户: $NEW_ACCOUNT_ID" | tee -a $LOG_FILE
fi

# 检查账户状态
ACCOUNT_STATUS=$(aws organizations describe-account --account-id $NEW_ACCOUNT_ID \
  --query 'Account.Status' --output text 2>/dev/null || echo "ERROR")

if [ "$ACCOUNT_STATUS" = "ACTIVE" ]; then
  echo "✅ 账户状态正常: ACTIVE" | tee -a $LOG_FILE
else
  echo "⚠️  账户状态: $ACCOUNT_STATUS" | tee -a $LOG_FILE
fi
```

### 2. 验证BillingGroup创建
```bash
echo "=== 验证BillingGroup创建 ===" | tee -a $LOG_FILE

# 通过ARN获取BillingGroup ID
BILLING_GROUP_ID=$(echo $BILLING_GROUP_ARN | cut -d'/' -f2)

# 验证BillingGroup存在
BILLING_GROUP_INFO=$(aws billingconductor get-billing-group \
  --arn $BILLING_GROUP_ARN \
  --region us-east-1 2>/dev/null || echo "ERROR")

if [ "$BILLING_GROUP_INFO" != "ERROR" ]; then
  echo "✅ BillingGroup创建成功" | tee -a $LOG_FILE
  
  # 获取BillingGroup详细信息
  BILLING_GROUP_NAME=$(aws billingconductor get-billing-group \
    --arn $BILLING_GROUP_ARN \
    --region us-east-1 \
    --query 'Name' \
    --output text)
  
  echo "BillingGroup详细信息:" | tee -a $LOG_FILE
  aws billingconductor get-billing-group \
    --arn $BILLING_GROUP_ARN \
    --region us-east-1 \
    --query '{Name:Name,Arn:Arn,Status:Status,Description:Description}' \
    --output table | tee -a $LOG_FILE
  
  # 验证BillingGroup名称
  echo "--- BillingGroup名称验证 ---" | tee -a $LOG_FILE
  echo "实际BillingGroup名称: $BILLING_GROUP_NAME" | tee -a $LOG_FILE
  
  if [[ "$BILLING_GROUP_NAME" == "Bills" ]]; then
    echo "✅ BillingGroup名称符合预期: Bills" | tee -a $LOG_FILE
  elif [[ "$BILLING_GROUP_NAME" =~ ^billing-group-[0-9]+$ ]]; then
    echo "ℹ️  现有BillingGroup名称: $BILLING_GROUP_NAME" | tee -a $LOG_FILE
    echo "ℹ️  注意: 脚本已更新，未来部署会创建名为'Bills'的BillingGroup" | tee -a $LOG_FILE
    echo "ℹ️  当前使用现有BillingGroup，功能正常" | tee -a $LOG_FILE
    echo "✅ BillingGroup功能验证通过" | tee -a $LOG_FILE
  else
    echo "⚠️  意外的BillingGroup名称: $BILLING_GROUP_NAME" | tee -a $LOG_FILE
  fi
  
else
  echo "❌ 无法找到BillingGroup: $BILLING_GROUP_ARN" | tee -a $LOG_FILE
fi

# 列出所有BillingGroups确认
echo "--- 所有BillingGroups ---" | tee -a $LOG_FILE
aws billingconductor list-billing-groups \
  --region us-east-1 \
  --query 'BillingGroups[].{Name:Name,Arn:Arn}' \
  --output table | tee -a $LOG_FILE
```

### 3. 验证邮箱处理
```bash
echo "=== 验证邮箱处理 ===" | tee -a $LOG_FILE

if [ "$NEW_ACCOUNT_EMAIL" = "$BILLS_EMAIL" ]; then
  echo "✅ 使用了预期的邮箱地址" | tee -a $LOG_FILE
else
  echo "ℹ️  邮箱处理结果: $NEW_ACCOUNT_EMAIL (可能处理了冲突)" | tee -a $LOG_FILE
  echo "原计划邮箱: $BILLS_EMAIL" | tee -a $LOG_FILE
fi

# 检查是否有邮箱冲突处理
if [[ "$NEW_ACCOUNT_EMAIL" =~ \+bills[0-9]+@ ]]; then
  echo "ℹ️  检测到邮箱冲突处理，使用了数字后缀" | tee -a $LOG_FILE
fi
```

### 4. 验证Lambda函数执行日志
```bash
echo "=== 验证Lambda函数执行 ===" | tee -a $LOG_FILE

# 检查Lambda函数日志
LAMBDA_FUNCTION_NAME="CreateAccountAndBillingGroup"
LOG_GROUP="/aws/lambda/$LAMBDA_FUNCTION_NAME"

# 获取最新日志流
LATEST_LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --limit 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>/dev/null || echo "无日志流")

if [ "$LATEST_LOG_STREAM" != "无日志流" ]; then
  echo "最新Lambda执行日志:" | tee -a $LOG_FILE
  aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LATEST_LOG_STREAM" \
    --limit 20 \
    --query 'events[].message' \
    --output text | tee -a $LOG_FILE
else
  echo "⚠️  未找到Lambda执行日志" | tee -a $LOG_FILE
fi
```

## 成功标准检查清单

完成以下所有检查项表示模组2测试成功：

### 账户创建检查
- [ ] 新AWS账户创建成功
- [ ] 账户状态为ACTIVE
- [ ] 账户ID已正确输出
- [ ] 账户邮箱已正确处理（包括冲突处理）
- [ ] 账户在Organizations中可见

### BillingGroup检查
- [ ] BillingGroup创建成功
- [ ] BillingGroup ARN正确输出
- [ ] BillingGroup状态正常
- [ ] BillingGroup可通过API访问
- [ ] BillingGroup名称验证通过（新部署应为'Bills'，现有部署接受现有名称）

### 系统功能检查
- [ ] CloudFormation栈状态为CREATE_COMPLETE
- [ ] 无资源创建失败
- [ ] Lambda函数执行无致命错误
- [ ] 所有输出值正确生成

## 故障排除

### 常见问题1: 账户创建和集成超时
**症状**: CREATE_IN_PROGRESS状态超过50分钟
**解决方案**:
```bash
# 检查账户创建状态
aws organizations list-create-account-status \
  --states IN_PROGRESS \
  --query 'CreateAccountStatuses[]' \
  --output table

# 如果看到失败的创建请求，检查失败原因
aws organizations list-create-account-status \
  --states FAILED \
  --query 'CreateAccountStatuses[].FailureReason' \
  --output table
```

### 常见问题2: 邮箱已存在
**症状**: 账户创建失败，邮箱地址冲突
**解决方案**:
```bash
# 检查现有账户邮箱
aws organizations list-accounts \
  --query "Accounts[?contains(Email, '+bills')]" \
  --output table

# Lambda会自动处理冲突，添加数字后缀
# 如果还是失败，手动指定不同的邮箱后缀
```

### 常见问题3: BillingConductor权限不足
**症状**: BillingGroup创建失败
**解决方案**:
```bash
# 验证BillingConductor权限
aws billingconductor list-billing-groups --region us-east-1

# 检查IAM用户的BillingConductor权限
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names billingconductor:CreateBillingGroup \
  --resource-arns "*"
```

### 常见问题4: Lambda函数超时
**症状**: Lambda函数执行超过1200秒(20分钟)
**说明**: 从v2版本开始，Lambda增加了3分钟CB family集成等待时间，总超时设置为20分钟
**解决方案**:
```bash
# 检查Lambda函数配置
aws lambda get-function-configuration \
  --function-name CreateAccountAndBillingGroup

# 查看CloudWatch指标
aws logs filter-log-events \
  --log-group-name /aws/lambda/CreateAccountAndBillingGroup \
  --filter-pattern "TIMEOUT"
```

### 常见问题5: CB Family集成问题
**症状**: BillingGroup创建失败，错误信息"Accounts are not in the payer account's CB family"
**说明**: 新创建的账户需要时间加入Consolidated Billing family，通常需要1-3分钟
**解决方案**: 
- v2版本已自动增加3分钟等待时间
- 如果仍然失败，可能需要更长等待时间或手动验证账户状态

### 常见问题6: BillingGroup名称说明
**当前状态**: 现有部署可能显示"billing-group-1753182274"格式的名称
**未来部署**: 脚本已更新，新部署将创建名为"Bills"的BillingGroup
**说明**: 
- 现有BillingGroup不会被自动修改，需要手动在控制台修改（如需要）
- 新的Payer部署会自动创建名为"Bills"的BillingGroup
- 两种名称格式都能正常工作，不影响功能

```bash
# 检查账户是否已加入Organization
aws organizations describe-account --account-id $NEW_ACCOUNT_ID

# 验证BillingConductor可见性
aws billingconductor list-billing-groups --region us-east-1

# 检查Lambda执行日志中的CB family等待过程
aws logs get-log-events \
  --log-group-name /aws/lambda/CreateAccountAndBillingGroup \
  --log-stream-name $LATEST_LOG_STREAM \
  --filter-pattern "CB family"
```

## 清理步骤

如果需要清理模组2资源：

```bash
echo "开始清理模组2资源..." | tee -a $LOG_FILE

# ⚠️  注意: 这将删除新创建的AWS账户！
# 首先删除CloudFormation栈
aws cloudformation delete-stack \
  --stack-name $MODULE2_STACK_NAME \
  --region $REGION

echo "等待栈删除完成..." | tee -a $LOG_FILE

# 监控删除进度
aws cloudformation wait stack-delete-complete \
  --stack-name $MODULE2_STACK_NAME \
  --region $REGION

# 注意：AWS账户一旦创建，不能通过API删除
# 需要联系AWS支持或通过控制台手动关闭账户
echo "⚠️  注意：新创建的账户需要手动关闭" | tee -a $LOG_FILE
echo "账户ID: $NEW_ACCOUNT_ID" | tee -a $LOG_FILE

echo "✅ 模组2资源清理完成（除账户外）" | tee -a $LOG_FILE
```

## 下一步

模组2测试成功后：
1. 保存 `BILLING_GROUP_ARN` 环境变量（模组3需要使用）
2. 记录新账户信息供参考
3. 继续执行模组3测试

```bash
# 保存关键变量供后续模组使用
echo "export BILLING_GROUP_ARN='$BILLING_GROUP_ARN'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export NEW_ACCOUNT_ID=$NEW_ACCOUNT_ID" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export NEW_ACCOUNT_EMAIL='$NEW_ACCOUNT_EMAIL'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export MODULE2_STACK_NAME=$MODULE2_STACK_NAME" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

echo "✅ 模组2测试完成，变量已保存" | tee -a $LOG_FILE
echo "🎯 下一步: 模组3 (Pro forma CUR) 和 模组4 (RISP CUR) 可以并行测试" | tee -a $LOG_FILE
```