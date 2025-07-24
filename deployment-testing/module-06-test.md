# 模组6测试: 账户自动移动

## 测试状态
- ⏸️ **测试状态**: 未开始  
- 📅 **预计时间**: 5-10分钟
- 🎯 **成功标准**: 设置EventBridge规则和Lambda函数，自动移动新账户到Normal OU

## 模组概述

**功能**: 监控AWS Organizations事件，自动移动新账户
**创建资源**:
- EventBridge规则监控CreateAccountResult和AcceptHandshake事件
- Lambda函数自动将新账户移动到Normal OU
- 应用SCP限制防止购买预付费服务
- CloudTrail日志记录所有账户移动活动

## 前置条件检查

### 1. 验证模组1依赖
```bash
# 加载之前模组的输出变量
if [ -f "/Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh" ]; then
  source /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
  echo "✅ 已加载之前的模组变量"
else
  echo "❌ 未找到之前模组的变量，请先完成模组1测试"
  exit 1
fi

# 验证Normal OU ID存在
if [ -z "$NORMAL_OU_ID" ]; then
  echo "❌ Normal OU ID未设置，请先完成模组1测试"
  exit 1
fi

echo "✅ 模组1依赖验证通过"
echo "Normal OU ID: $NORMAL_OU_ID"
```

### 2. 验证EventBridge和CloudTrail权限
```bash
# 检查EventBridge权限
aws events list-rules --region us-east-1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ EventBridge权限正常"
else
  echo "❌ EventBridge权限有问题"
  exit 1
fi

# 检查CloudTrail权限
aws cloudtrail describe-trails --region us-east-1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ CloudTrail权限正常"
else
  echo "❌ CloudTrail权限有问题"
  exit 1
fi

# 检查Organizations权限
aws organizations describe-organization > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Organizations权限正常"
else
  echo "❌ Organizations权限有问题"
  exit 1
fi
```

### 3. 检查现有EventBridge规则
```bash
echo "检查现有EventBridge规则..."

# 列出现有的Organizations相关规则
aws events list-rules --region us-east-1 \
  --query 'Rules[?contains(Name, `Account`) || contains(Description, `Organizations`)].{Name:Name,State:State,Description:Description}' \
  --output table

# 检查CloudTrail状态
EXISTING_TRAILS=$(aws cloudtrail describe-trails --region us-east-1 \
  --query 'trailList[?IsMultiRegionTrail==`true`].{Name:Name,S3BucketName:S3BucketName,IsLogging:IsLogging}' \
  --output table)

if [ -n "$EXISTING_TRAILS" ]; then
  echo "✅ 发现现有CloudTrail:" 
  echo "$EXISTING_TRAILS"
else
  echo "ℹ️  未发现多区域CloudTrail，模组6可能会创建新的"
fi
```

## 部署步骤

### 步骤1: 设置环境变量
```bash
# 设置基础变量
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"
export MODULE6_STACK_NAME="${STACK_PREFIX}-account-auto-move-${TIMESTAMP}"

# 账户移动相关变量
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)

# 验证变量
echo "=== 模组6环境变量 ==="
echo "Stack Name: $MODULE6_STACK_NAME"
echo "Normal OU ID: $NORMAL_OU_ID"
echo "Master Account ID: $MASTER_ACCOUNT_ID"
echo "Region: $REGION"
```

### 步骤2: 验证CloudFormation模板
```bash
# 切换到项目目录
cd /Users/di.miao/Work/payer-setup/aws-payer-automation

# 验证模板语法
aws cloudformation validate-template \
  --template-body file://templates/06-account-auto-management/account_auto_move.yaml \
  --region $REGION

echo "✅ 模板验证通过"
```

### 步骤3: 创建日志文件
```bash
# 创建测试日志
export LOG_FILE="/Users/di.miao/Work/payer-setup/deployment-testing/logs/module-06-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

echo "$(date): 开始模组6部署测试" | tee -a $LOG_FILE
echo "Normal OU ID: $NORMAL_OU_ID" | tee -a $LOG_FILE
```

### 步骤4: 部署CloudFormation栈
```bash
# 部署栈
echo "开始部署模组6..." | tee -a $LOG_FILE

aws cloudformation create-stack \
  --stack-name $MODULE6_STACK_NAME \
  --template-body file://templates/06-account-auto-management/account_auto_move.yaml \
  --parameters ParameterKey=NormalOUId,ParameterValue="$NORMAL_OU_ID" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=TestModule,Value=Module6 Key=TestRun,Value=$TIMESTAMP

echo "栈创建请求已提交: $MODULE6_STACK_NAME" | tee -a $LOG_FILE
```

### 步骤5: 监控部署进度
```bash
# 监控栈创建状态
echo "监控栈部署状态..." | tee -a $LOG_FILE

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name $MODULE6_STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "PENDING")
  
  echo "$(date): 当前状态: $STATUS" | tee -a $LOG_FILE
  
  case $STATUS in
    "CREATE_COMPLETE")
      echo "✅ 栈创建成功!" | tee -a $LOG_FILE
      break
      ;;
    "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"ROLLBACK_FAILED")
      echo "❌ 栈创建失败: $STATUS" | tee -a $LOG_FILE
      # 获取失败原因
      aws cloudformation describe-stack-events \
        --stack-name $MODULE6_STACK_NAME \
        --region $REGION \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
        --output table | tee -a $LOG_FILE
      exit 1
      ;;
    "CREATE_IN_PROGRESS")
      echo "⏳ 继续等待..." | tee -a $LOG_FILE
      sleep 30
      ;;
    *)
      echo "⚠️  未知状态: $STATUS" | tee -a $LOG_FILE
      sleep 30
      ;;
  esac
done
```

### 步骤6: 获取部署结果
```bash
echo "=== 获取部署输出 ===" | tee -a $LOG_FILE

# 获取栈输出
export CLOUDTRAIL_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name $MODULE6_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailBucketName`].OutputValue' \
  --output text)

export CLOUDTRAIL_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE6_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailName`].OutputValue' \
  --output text)

export ACCOUNT_MOVER_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name $MODULE6_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`AccountMoverFunctionArn`].OutputValue' \
  --output text)

echo "CloudTrail存储桶: $CLOUDTRAIL_BUCKET" | tee -a $LOG_FILE
echo "CloudTrail名称: $CLOUDTRAIL_NAME" | tee -a $LOG_FILE
echo "账户移动函数ARN: $ACCOUNT_MOVER_FUNCTION" | tee -a $LOG_FILE
```

## 部署验证检查

### 1. 验证EventBridge规则创建
```bash
echo "=== 验证EventBridge规则创建 ===" | tee -a $LOG_FILE

# 列出新创建的规则
echo "--- 账户管理相关EventBridge规则 ---" | tee -a $LOG_FILE
aws events list-rules --region $REGION \
  --query 'Rules[?contains(Name, `Account`) || contains(Name, `Organization`)].{Name:Name,State:State,Description:Description}' \
  --output table | tee -a $LOG_FILE

# 检查特定规则的详细信息
RULE_NAMES=$(aws events list-rules --region $REGION \
  --query 'Rules[?contains(Name, `Account`)].Name' --output text)

for RULE_NAME in $RULE_NAMES; do
  if [ -n "$RULE_NAME" ]; then
    echo "--- 规则详情: $RULE_NAME ---" | tee -a $LOG_FILE
    aws events describe-rule --name "$RULE_NAME" --region $REGION | tee -a $LOG_FILE
    
    # 检查规则的目标
    echo "--- 规则目标 ---" | tee -a $LOG_FILE
    aws events list-targets-by-rule --rule "$RULE_NAME" --region $REGION \
      --query 'Targets[].{Id:Id,Arn:Arn}' --output table | tee -a $LOG_FILE
  fi
done
```

### 2. 验证Lambda函数创建
```bash
echo "=== 验证Lambda函数创建 ===" | tee -a $LOG_FILE

# 检查账户移动Lambda函数
ACCOUNT_MOVER_NAME="AccountAutoMover"
MOVER_EXISTS=$(aws lambda get-function --function-name $ACCOUNT_MOVER_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$MOVER_EXISTS" != "ERROR" ]; then
  echo "✅ 账户移动Lambda函数创建成功: $ACCOUNT_MOVER_NAME" | tee -a $LOG_FILE
  aws lambda get-function --function-name $ACCOUNT_MOVER_NAME --region $REGION \
    --query 'Configuration.{Name:FunctionName,Runtime:Runtime,Timeout:Timeout,Environment:Environment}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ 账户移动Lambda函数不存在: $ACCOUNT_MOVER_NAME" | tee -a $LOG_FILE
fi

# 检查CloudTrail管理Lambda函数
CLOUDTRAIL_MANAGER_NAME="CloudTrailManager"
MANAGER_EXISTS=$(aws lambda get-function --function-name $CLOUDTRAIL_MANAGER_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$MANAGER_EXISTS" != "ERROR" ]; then
  echo "✅ CloudTrail管理Lambda函数创建成功: $CLOUDTRAIL_MANAGER_NAME" | tee -a $LOG_FILE
else
  echo "ℹ️  CloudTrail管理Lambda函数可能使用不同名称" | tee -a $LOG_FILE
fi
```

### 3. 验证CloudTrail配置
```bash
echo "=== 验证CloudTrail配置 ===" | tee -a $LOG_FILE

if [ -n "$CLOUDTRAIL_NAME" ]; then
  # 检查CloudTrail状态
  echo "--- CloudTrail基本信息 ---" | tee -a $LOG_FILE
  aws cloudtrail describe-trails --trail-name-list $CLOUDTRAIL_NAME --region $REGION | tee -a $LOG_FILE
  
  # 检查CloudTrail日志状态
  echo "--- CloudTrail日志状态 ---" | tee -a $LOG_FILE
  aws cloudtrail get-trail-status --name $CLOUDTRAIL_NAME --region $REGION | tee -a $LOG_FILE
  
  # 检查S3存储桶权限
  if [ -n "$CLOUDTRAIL_BUCKET" ]; then
    echo "--- CloudTrail S3存储桶策略 ---" | tee -a $LOG_FILE
    aws s3api get-bucket-policy --bucket $CLOUDTRAIL_BUCKET 2>/dev/null || echo "无存储桶策略或获取失败"
  fi
else
  echo "⚠️  CloudTrail名称未获取到，可能使用现有CloudTrail" | tee -a $LOG_FILE
fi
```

### 4. 验证IAM角色和权限
```bash
echo "=== 验证IAM角色和权限 ===" | tee -a $LOG_FILE

# 检查Lambda执行角色
LAMBDA_ROLE_NAME="AccountAutoMoverRole"
ROLE_EXISTS=$(aws iam get-role --role-name $LAMBDA_ROLE_NAME 2>/dev/null || echo "ERROR")

if [ "$ROLE_EXISTS" != "ERROR" ]; then
  echo "✅ Lambda执行角色存在: $LAMBDA_ROLE_NAME" | tee -a $LOG_FILE
  
  # 检查角色的策略
  echo "--- 角色附加的策略 ---" | tee -a $LOG_FILE
  aws iam list-attached-role-policies --role-name $LAMBDA_ROLE_NAME | tee -a $LOG_FILE
  
  # 检查内联策略
  echo "--- 角色内联策略 ---" | tee -a $LOG_FILE
  aws iam list-role-policies --role-name $LAMBDA_ROLE_NAME | tee -a $LOG_FILE
else
  echo "⚠️  Lambda执行角色可能使用不同名称" | tee -a $LOG_FILE
fi
```

### 5. 测试账户移动功能（模拟）
```bash
echo "=== 测试账户移动功能 ===" | tee -a $LOG_FILE

# 列出当前Normal OU中的账户
echo "--- Normal OU中的当前账户 ---" | tee -a $LOG_FILE
aws organizations list-accounts-for-parent --parent-id $NORMAL_OU_ID \
  --query 'Accounts[].{Id:Id,Name:Name,Email:Email}' --output table | tee -a $LOG_FILE

NORMAL_OU_COUNT=$(aws organizations list-accounts-for-parent --parent-id $NORMAL_OU_ID \
  --query 'length(Accounts)' --output text)
echo "Normal OU中的账户数量: $NORMAL_OU_COUNT" | tee -a $LOG_FILE

# 检查其他OU中的账户
echo "--- Root下的其他账户 ---" | tee -a $LOG_FILE
export ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations list-accounts-for-parent --parent-id $ROOT_ID \
  --query 'Accounts[].{Id:Id,Name:Name,Email:Email}' --output table | tee -a $LOG_FILE

# 注意：实际的账户移动测试需要创建新账户或邀请账户加入
echo "ℹ️  要测试自动移动功能，需要创建新账户或邀请现有账户加入Organization" | tee -a $LOG_FILE
```

### 6. 验证EventBridge与Lambda集成
```bash
echo "=== 验证EventBridge与Lambda集成 ===" | tee -a $LOG_FILE

# 检查Lambda函数的EventBridge触发器
if [ -n "$ACCOUNT_MOVER_NAME" ]; then
  echo "--- Lambda函数的触发器配置 ---" | tee -a $LOG_FILE
  aws lambda list-event-source-mappings --function-name $ACCOUNT_MOVER_NAME --region $REGION 2>/dev/null || echo "无事件源映射"
  
  # 检查Lambda函数的权限策略
  echo "--- Lambda函数权限策略 ---" | tee -a $LOG_FILE
  aws lambda get-policy --function-name $ACCOUNT_MOVER_NAME --region $REGION 2>/dev/null || echo "无资源策略"
fi
```

### 7. 检查Lambda执行日志
```bash
echo "=== 检查Lambda执行日志 ===" | tee -a $LOG_FILE

# 检查账户移动函数的日志
LOG_GROUP="/aws/lambda/AccountAutoMover"
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
    --limit 10 \
    --query 'events[].message' \
    --output text | tee -a $LOG_FILE
else
  echo "ℹ️  暂无Lambda执行日志（等待事件触发）" | tee -a $LOG_FILE
fi
```

## 成功标准检查清单

完成以下所有检查项表示模组6测试成功：

### EventBridge规则检查
- [ ] 账户创建事件监控规则创建成功
- [ ] 账户邀请接受事件监控规则创建成功  
- [ ] EventBridge规则状态为ENABLED
- [ ] 规则正确配置事件模式

### Lambda函数检查
- [ ] 账户移动Lambda函数创建成功
- [ ] Lambda函数权限配置正确
- [ ] Lambda函数环境变量设置正确（Normal OU ID）
- [ ] Lambda函数超时设置适当（60秒）

### CloudTrail检查
- [ ] CloudTrail创建或配置成功
- [ ] CloudTrail日志记录已启用
- [ ] S3存储桶权限配置正确
- [ ] 多区域日志记录已启用

### IAM权限检查
- [ ] Lambda执行角色创建并配置正确
- [ ] Organizations管理权限已授予
- [ ] CloudTrail访问权限已授予

### 系统功能检查
- [ ] CloudFormation栈状态为CREATE_COMPLETE
- [ ] 无资源创建失败
- [ ] 所有输出值正确生成

## 故障排除

### 常见问题1: EventBridge权限错误
**症状**: EventBridge规则创建失败或无法触发Lambda
**解决方案**:
```bash
# 检查EventBridge权限
aws events list-rules --region $REGION

# 检查Lambda函数的资源策略
aws lambda get-policy --function-name AccountAutoMover

# 手动添加EventBridge权限（如需要）
aws lambda add-permission \
  --function-name AccountAutoMover \
  --statement-id allow-eventbridge \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com
```

### 常见问题2: CloudTrail创建失败
**症状**: CloudTrail创建失败或S3权限错误
**解决方案**:
```bash
# 检查现有CloudTrail
aws cloudtrail describe-trails

# 检查S3存储桶策略
aws s3api get-bucket-policy --bucket $CLOUDTRAIL_BUCKET

# 验证CloudTrail服务权限
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names cloudtrail:CreateTrail \
  --resource-arns "*"
```

### 常见问题3: Lambda函数权限不足
**症状**: Lambda执行失败，Organizations权限被拒绝
**解决方案**:
```bash
# 检查Lambda执行角色权限
aws iam get-role-policy --role-name AccountAutoMoverRole --policy-name OrganizationsAccess

# 测试移动账户权限
aws organizations move-account \
  --account-id 123456789012 \
  --source-parent-id $ROOT_ID \
  --destination-parent-id $NORMAL_OU_ID \
  --dry-run 2>&1 || echo "权限或参数测试"
```

### 常见问题4: Normal OU ID无效
**症状**: Lambda函数无法找到目标OU
**解决方案**:
```bash
# 验证Normal OU ID
aws organizations describe-organizational-unit --organizational-unit-id $NORMAL_OU_ID

# 重新获取Normal OU ID
NORMAL_OU_ID=$(aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_ID \
  --query 'OrganizationalUnits[?Name==`Normal`].Id' \
  --output text)
echo "验证的Normal OU ID: $NORMAL_OU_ID"
```

## 功能测试

### 创建测试账户验证自动移动
如果您想测试自动移动功能，可以创建一个测试账户：

```bash
echo "=== 创建测试账户验证自动移动功能 ===" | tee -a $LOG_FILE
echo "⚠️  这将创建一个新的AWS账户，请谨慎操作" | tee -a $LOG_FILE

read -p "是否要创建测试账户验证自动移动功能？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # 生成测试账户邮箱
  TEST_EMAIL="${MASTER_ACCOUNT_ID}+test$(date +%s)@example.com"  # 请使用有效邮箱域
  
  echo "创建测试账户: $TEST_EMAIL" | tee -a $LOG_FILE
  
  # 创建账户
  CREATE_RESPONSE=$(aws organizations create-account \
    --email $TEST_EMAIL \
    --account-name "Test Account for Auto Move" \
    --query 'CreateAccountStatus.Id' \
    --output text)
  
  echo "账户创建请求ID: $CREATE_RESPONSE" | tee -a $LOG_FILE
  echo "请监控EventBridge和Lambda日志，观察自动移动过程" | tee -a $LOG_FILE
  
  # 等待一段时间后检查结果
  echo "等待30秒后检查账户创建状态..." | tee -a $LOG_FILE
  sleep 30
  
  # 检查创建状态
  aws organizations describe-create-account-status \
    --create-account-request-id $CREATE_RESPONSE | tee -a $LOG_FILE
else
  echo "跳过测试账户创建" | tee -a $LOG_FILE
fi
```

## 清理步骤

如果需要清理模组6资源：

```bash
echo "开始清理模组6资源..." | tee -a $LOG_FILE

# 删除EventBridge规则
RULE_NAMES=$(aws events list-rules --region $REGION \
  --query 'Rules[?contains(Name, `Account`)].Name' --output text)

for RULE_NAME in $RULE_NAMES; do
  if [ -n "$RULE_NAME" ]; then
    echo "删除EventBridge规则: $RULE_NAME" | tee -a $LOG_FILE
    # 先删除规则目标
    aws events remove-targets --rule "$RULE_NAME" --ids "1" --region $REGION
    # 再删除规则
    aws events delete-rule --name "$RULE_NAME" --region $REGION
  fi
done

# 删除CloudFormation栈
aws cloudformation delete-stack \
  --stack-name $MODULE6_STACK_NAME \
  --region $REGION

echo "等待栈删除完成..." | tee -a $LOG_FILE

# 监控删除进度
aws cloudformation wait stack-delete-complete \
  --stack-name $MODULE6_STACK_NAME \
  --region $REGION

echo "✅ 模组6资源清理完成" | tee -a $LOG_FILE
```

## 下一步

模组6测试成功后：
1. 保存相关变量供参考
2. 账户自动移动功能现在已激活
3. 可以继续执行模组7测试

```bash
# 保存关键变量供参考
echo "export CLOUDTRAIL_BUCKET='$CLOUDTRAIL_BUCKET'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export CLOUDTRAIL_NAME='$CLOUDTRAIL_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export MODULE6_STACK_NAME='$MODULE6_STACK_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

echo "✅ 模组6测试完成，变量已保存" | tee -a $LOG_FILE
echo "🎯 下一步: 继续模组7 (CloudFront监控) 测试" | tee -a $LOG_FILE
echo "ℹ️  账户自动移动功能现在已激活，新账户将自动移动到Normal OU" | tee -a $LOG_FILE
echo "📝 监控提示: 可通过CloudWatch Logs查看Lambda函数执行日志" | tee -a $LOG_FILE
```