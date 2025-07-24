# 模组7测试: CloudFront跨账户监控

## 测试状态
- ⏸️ **测试状态**: 未开始
- 📅 **预计时间**: 15-20分钟（包含StackSet部署）
- 🎯 **成功标准**: 设置OAM基础设施、CloudFront监控告警和Telegram通知

## 模组概述

**功能**: 智能CloudFront跨账户监控系统
**创建资源**:
- OAM (Observability Access Manager) Sink基础设施
- 跨账户CloudFront流量集中监控
- 100MB阈值告警（可配置）
- Telegram Bot实时通知
- StackSet自动部署OAM Link到成员账户

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

# 获取Payer名称
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
export PAYER_NAME=$(aws organizations describe-account --account-id $MASTER_ACCOUNT_ID --query 'Account.Name' --output text)

echo "✅ 模组1依赖验证通过"
echo "Normal OU ID: $NORMAL_OU_ID"
echo "Master Account ID: $MASTER_ACCOUNT_ID"
echo "Payer Name: $PAYER_NAME"
```

### 2. 验证CloudFormation StackSets权限
```bash
# 检查CloudFormation权限
aws cloudformation list-stacks --region us-east-1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ CloudFormation权限正常"
else
  echo "❌ CloudFormation权限有问题"
  exit 1
fi

# 检查Organizations StackSets信任关系
TRUSTED_ACCESS=$(aws organizations list-aws-service-access-for-organization \
  --query 'EnabledServicePrincipals[?ServicePrincipal==`stacksets.cloudformation.amazonaws.com`]' \
  --output text 2>/dev/null)

if [ -n "$TRUSTED_ACCESS" ]; then
  echo "✅ CloudFormation StackSets信任访问已启用"
else
  echo "ℹ️  CloudFormation StackSets信任访问未启用，模组7会自动启用"
fi
```

### 3. 验证CloudWatch和SNS权限
```bash
# 检查CloudWatch权限
aws cloudwatch list-metrics --region us-east-1 --max-items 1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ CloudWatch权限正常"
else
  echo "❌ CloudWatch权限有问题"
  exit 1
fi

# 检查SNS权限
aws sns list-topics --region us-east-1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ SNS权限正常"
else
  echo "❌ SNS权限有问题"
  exit 1
fi

# 检查OAM权限（AWS Observability Access Manager）
aws oam list-sinks --region us-east-1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ OAM权限正常"
else
  echo "⚠️  OAM权限可能有问题，但继续测试"
fi
```

### 4. 验证Normal OU中的成员账户
```bash
echo "检查Normal OU中的成员账户..."

# 列出Normal OU中的账户
MEMBER_ACCOUNTS=$(aws organizations list-accounts-for-parent --parent-id $NORMAL_OU_ID \
  --query 'Accounts[].{Id:Id,Name:Name,Email:Email}' --output table)

MEMBER_COUNT=$(aws organizations list-accounts-for-parent --parent-id $NORMAL_OU_ID \
  --query 'length(Accounts)' --output text)

echo "Normal OU中的成员账户 ($MEMBER_COUNT 个):"
echo "$MEMBER_ACCOUNTS"

if [ $MEMBER_COUNT -gt 0 ]; then
  echo "✅ Normal OU中有成员账户，StackSet将部署OAM Link" 
else
  echo "ℹ️  Normal OU中暂无成员账户，StackSet将等待账户加入后自动部署"
fi
```

## 部署步骤

### 步骤1: 设置环境变量
```bash
# 设置基础变量
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"
export MODULE7_STACK_NAME="${STACK_PREFIX}-cloudfront-monitoring-${TIMESTAMP}"

# CloudFront监控参数
export CLOUDFRONT_THRESHOLD_MB="100"  # 100MB阈值
export TELEGRAM_GROUP_ID="-862835857"  # 默认Telegram组ID（请根据实际情况修改）

# StackSet相关
export STACKSET_NAME="${PAYER_NAME}-OAM-Links"

# 验证变量
echo "=== 模组7环境变量 ==="
echo "Stack Name: $MODULE7_STACK_NAME"
echo "Payer Name: $PAYER_NAME"
echo "CloudFront Threshold: ${CLOUDFRONT_THRESHOLD_MB}MB"
echo "Telegram Group ID: $TELEGRAM_GROUP_ID"
echo "StackSet Name: $STACKSET_NAME"
echo "Normal OU ID: $NORMAL_OU_ID"
echo "Region: $REGION"
```

### 步骤2: 验证CloudFormation模板
```bash
# 切换到项目目录
cd /Users/di.miao/Work/payer-setup/aws-payer-automation

# 验证主模板语法
aws cloudformation validate-template \
  --template-body file://templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml \
  --region $REGION

echo "✅ 主模板验证通过"

# 验证StackSet模板语法
aws cloudformation validate-template \
  --template-body file://templates/07-cloudfront-monitoring/oam-link-stackset.yaml \
  --region $REGION

echo "✅ StackSet模板验证通过"
```

### 步骤3: 创建日志文件
```bash
# 创建测试日志
export LOG_FILE="/Users/di.miao/Work/payer-setup/deployment-testing/logs/module-07-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

echo "$(date): 开始模组7部署测试" | tee -a $LOG_FILE
echo "Payer Name: $PAYER_NAME" | tee -a $LOG_FILE
echo "CloudFront Threshold: ${CLOUDFRONT_THRESHOLD_MB}MB" | tee -a $LOG_FILE
echo "Telegram Group ID: $TELEGRAM_GROUP_ID" | tee -a $LOG_FILE
```

### 步骤4: 启用StackSets信任访问
```bash
echo "启用CloudFormation StackSets信任访问..." | tee -a $LOG_FILE

# 检查是否已启用
TRUSTED_ACCESS=$(aws organizations list-aws-service-access-for-organization \
  --query 'EnabledServicePrincipals[?ServicePrincipal==`stacksets.cloudformation.amazonaws.com`]' \
  --output text 2>/dev/null)

if [ -z "$TRUSTED_ACCESS" ]; then
  aws organizations enable-aws-service-access \
    --service-principal stacksets.cloudformation.amazonaws.com
  echo "✅ CloudFormation StackSets信任访问已启用" | tee -a $LOG_FILE
else
  echo "✅ CloudFormation StackSets信任访问已存在" | tee -a $LOG_FILE
fi
```

### 步骤5: 部署CloudFormation栈（第一阶段）
```bash
# 部署主要基础设施栈
echo "开始部署模组7基础设施..." | tee -a $LOG_FILE

aws cloudformation create-stack \
  --stack-name $MODULE7_STACK_NAME \
  --template-body file://templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml \
  --parameters \
      ParameterKey=PayerName,ParameterValue="$PAYER_NAME" \
      ParameterKey=CloudFrontThresholdMB,ParameterValue="$CLOUDFRONT_THRESHOLD_MB" \
      ParameterKey=TelegramGroupId,ParameterValue="$TELEGRAM_GROUP_ID" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=TestModule,Value=Module7 Key=TestRun,Value=$TIMESTAMP

echo "栈创建请求已提交: $MODULE7_STACK_NAME" | tee -a $LOG_FILE
```

### 步骤6: 监控第一阶段部署进度
```bash
# 监控栈创建状态
echo "监控基础设施栈部署状态..." | tee -a $LOG_FILE
START_TIME=$(date +%s)

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name $MODULE7_STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "PENDING")
  
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  ELAPSED_MIN=$((ELAPSED / 60))
  
  echo "$(date): 当前状态: $STATUS (已等待: ${ELAPSED_MIN}分钟)" | tee -a $LOG_FILE
  
  case $STATUS in
    "CREATE_COMPLETE")
      echo "✅ 基础设施栈创建成功! 用时: ${ELAPSED_MIN}分钟" | tee -a $LOG_FILE
      break
      ;;
    "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"ROLLBACK_FAILED")
      echo "❌ 基础设施栈创建失败: $STATUS (用时: ${ELAPSED_MIN}分钟)" | tee -a $LOG_FILE
      # 获取失败原因
      aws cloudformation describe-stack-events \
        --stack-name $MODULE7_STACK_NAME \
        --region $REGION \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
        --output table | tee -a $LOG_FILE
      exit 1
      ;;
    "CREATE_IN_PROGRESS")
      if [ $ELAPSED_MIN -gt 15 ]; then
        echo "⚠️  部署时间超过15分钟，可能有问题" | tee -a $LOG_FILE
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

### 步骤7: 获取第一阶段部署结果
```bash
echo "=== 获取基础设施栈输出 ===" | tee -a $LOG_FILE

# 获取OAM Sink ARN
export MONITORING_SINK_ARN=$(aws cloudformation describe-stacks \
  --stack-name $MODULE7_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`MonitoringSinkArn`].OutputValue' \
  --output text)

export CLOUDFRONT_ALARM_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE7_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontAlarmName`].OutputValue' \
  --output text)

export ALERT_FUNCTION_ARN=$(aws cloudformation describe-stacks \
  --stack-name $MODULE7_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`AlertFunctionArn`].OutputValue' \
  --output text)

echo "Monitoring Sink ARN: $MONITORING_SINK_ARN" | tee -a $LOG_FILE
echo "CloudFront Alarm Name: $CLOUDFRONT_ALARM_NAME" | tee -a $LOG_FILE
echo "Alert Function ARN: $ALERT_FUNCTION_ARN" | tee -a $LOG_FILE
```

### 步骤8: 创建和部署StackSet（第二阶段）
```bash
echo "=== 创建和部署StackSet ===" | tee -a $LOG_FILE

# 创建StackSet
echo "创建StackSet: $STACKSET_NAME" | tee -a $LOG_FILE

aws cloudformation create-stack-set \
  --stack-set-name "$STACKSET_NAME" \
  --template-body file://templates/07-cloudfront-monitoring/oam-link-stackset.yaml \
  --parameters \
      ParameterKey=OAMSinkArn,ParameterValue="$MONITORING_SINK_ARN" \
      ParameterKey=PayerName,ParameterValue="$PAYER_NAME" \
  --capabilities CAPABILITY_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --description "Deploy OAM Links for CloudFront monitoring across member accounts" \
  --region $REGION

echo "StackSet创建请求已提交" | tee -a $LOG_FILE

# 等待StackSet创建完成
echo "等待StackSet创建完成..." | tee -a $LOG_FILE
sleep 30

# 检查StackSet状态
STACKSET_STATUS=$(aws cloudformation describe-stack-set \
  --stack-set-name "$STACKSET_NAME" \
  --region $REGION \
  --query 'StackSet.Status' \
  --output text 2>/dev/null || echo "ERROR")

if [ "$STACKSET_STATUS" = "ACTIVE" ]; then
  echo "✅ StackSet创建成功: $STACKSET_NAME" | tee -a $LOG_FILE
else
  echo "❌ StackSet创建失败或状态异常: $STACKSET_STATUS" | tee -a $LOG_FILE
fi
```

### 步骤9: 部署StackSet到Normal OU
```bash
echo "部署StackSet到Normal OU..." | tee -a $LOG_FILE

# 部署StackSet实例到Normal OU
aws cloudformation create-stack-instances \
  --stack-set-name "$STACKSET_NAME" \
  --deployment-targets OrganizationalUnitIds="$NORMAL_OU_ID" \
  --regions "$REGION" \
  --region "$REGION"

echo "StackSet实例部署请求已提交到Normal OU" | tee -a $LOG_FILE

# 监控StackSet部署进度
echo "监控StackSet部署进度（这可能需要几分钟）..." | tee -a $LOG_FILE
sleep 60  # 等待部署开始

# 检查部署操作状态
OPERATION_ID=$(aws cloudformation list-stack-set-operations \
  --stack-set-name "$STACKSET_NAME" \
  --region $REGION \
  --query 'Summaries[0].OperationId' \
  --output text)

if [ "$OPERATION_ID" != "None" ] && [ -n "$OPERATION_ID" ]; then
  echo "StackSet操作ID: $OPERATION_ID" | tee -a $LOG_FILE
  
  # 监控操作状态
  for i in {1..10}; do
    OPERATION_STATUS=$(aws cloudformation describe-stack-set-operation \
      --stack-set-name "$STACKSET_NAME" \
      --operation-id "$OPERATION_ID" \
      --region $REGION \
      --query 'StackSetOperation.Status' \
      --output text 2>/dev/null || echo "UNKNOWN")
    
    echo "$(date): StackSet操作状态: $OPERATION_STATUS (检查 $i/10)" | tee -a $LOG_FILE
    
    case $OPERATION_STATUS in
      "SUCCEEDED")
        echo "✅ StackSet部署成功!" | tee -a $LOG_FILE
        break
        ;;
      "FAILED"|"STOPPED")
        echo "❌ StackSet部署失败: $OPERATION_STATUS" | tee -a $LOG_FILE
        break
        ;;
      "RUNNING")
        echo "⏳ StackSet部署进行中..." | tee -a $LOG_FILE
        sleep 60
        ;;
      *)
        echo "⚠️  StackSet状态: $OPERATION_STATUS" | tee -a $LOG_FILE
        sleep 30
        ;;
    esac
  done
else
  echo "⚠️  无法获取StackSet操作ID，可能部署有问题" | tee -a $LOG_FILE
fi
```

## 部署验证检查

### 1. 验证OAM Sink创建
```bash
echo "=== 验证OAM Sink创建 ===" | tee -a $LOG_FILE

# 列出所有OAM Sinks
aws oam list-sinks --region $REGION \
  --query 'Items[].{Name:Name,Id:Id,Arn:Arn}' \
  --output table | tee -a $LOG_FILE

# 检查我们创建的Sink
if [ -n "$MONITORING_SINK_ARN" ]; then
  SINK_ID=$(echo $MONITORING_SINK_ARN | cut -d'/' -f2)
  echo "--- 监控Sink详细信息 ---" | tee -a $LOG_FILE
  aws oam get-sink --identifier $SINK_ID --region $REGION | tee -a $LOG_FILE
else
  echo "⚠️  未找到Monitoring Sink ARN" | tee -a $LOG_FILE
fi
```

### 2. 验证CloudWatch告警创建
```bash
echo "=== 验证CloudWatch告警创建 ===" | tee -a $LOG_FILE

# 检查CloudFront相关告警
if [ -n "$CLOUDFRONT_ALARM_NAME" ]; then
  echo "--- CloudFront告警详细信息 ---" | tee -a $LOG_FILE
  aws cloudwatch describe-alarms --alarm-names "$CLOUDFRONT_ALARM_NAME" --region $REGION | tee -a $LOG_FILE
else
  echo "⚠️  CloudFront告警名称未获取到" | tee -a $LOG_FILE
fi

# 列出所有CloudFront相关告警
echo "--- 所有CloudFront相关告警 ---" | tee -a $LOG_FILE
aws cloudwatch describe-alarms --region $REGION \
  --query 'MetricAlarms[?contains(AlarmName, `CloudFront`)].{Name:AlarmName,State:StateValue,Threshold:Threshold}' \
  --output table | tee -a $LOG_FILE
```

### 3. 验证Lambda告警函数
```bash
echo "=== 验证Lambda告警函数 ===" | tee -a $LOG_FILE

# 检查CloudFront告警Lambda函数
ALERT_LAMBDA_NAME="${PAYER_NAME}-CloudFront-Alert"
ALERT_EXISTS=$(aws lambda get-function --function-name $ALERT_LAMBDA_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$ALERT_EXISTS" != "ERROR" ]; then
  echo "✅ CloudFront告警Lambda函数创建成功: $ALERT_LAMBDA_NAME" | tee -a $LOG_FILE
  aws lambda get-function --function-name $ALERT_LAMBDA_NAME --region $REGION \
    --query 'Configuration.{Name:FunctionName,Runtime:Runtime,Timeout:Timeout,Environment:Environment}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ CloudFront告警Lambda函数不存在: $ALERT_LAMBDA_NAME" | tee -a $LOG_FILE
fi

# 检查OAM设置Lambda函数
OAM_LAMBDA_NAME="${PAYER_NAME}-OAM-Setup"
OAM_EXISTS=$(aws lambda get-function --function-name $OAM_LAMBDA_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$OAM_EXISTS" != "ERROR" ]; then
  echo "✅ OAM设置Lambda函数创建成功: $OAM_LAMBDA_NAME" | tee -a $LOG_FILE
else
  echo "ℹ️  OAM设置Lambda函数可能使用不同名称" | tee -a $LOG_FILE
fi
```

### 4. 验证StackSet部署状态
```bash
echo "=== 验证StackSet部署状态 ===" | tee -a $LOG_FILE

# 检查StackSet基本信息
aws cloudformation describe-stack-set \
  --stack-set-name "$STACKSET_NAME" \
  --region $REGION \
  --query 'StackSet.{Name:StackSetName,Status:Status,Description:Description}' \
  --output table | tee -a $LOG_FILE

# 列出StackSet实例
echo "--- StackSet实例状态 ---" | tee -a $LOG_FILE
aws cloudformation list-stack-instances \
  --stack-set-name "$STACKSET_NAME" \
  --region $REGION \
  --query 'Summaries[].{Account:Account,Region:Region,Status:Status,StatusReason:StatusReason}' \
  --output table | tee -a $LOG_FILE

# 检查StackSet操作历史
echo "--- StackSet操作历史 ---" | tee -a $LOG_FILE
aws cloudformation list-stack-set-operations \
  --stack-set-name "$STACKSET_NAME" \
  --region $REGION \
  --query 'Summaries[0:3].{OperationId:OperationId,Action:Action,Status:Status,CreationTimestamp:CreationTimestamp}' \
  --output table | tee -a $LOG_FILE
```

### 5. 验证OAM Links（在成员账户中）
```bash
echo "=== 验证OAM Links部署 ===" | tee -a $LOG_FILE

# 列出成员账户的OAM Links（如果有权限）
echo "--- 尝试列出OAM Links ---" | tee -a $LOG_FILE
aws oam list-links --region $REGION 2>/dev/null | tee -a $LOG_FILE || echo "无OAM Links或权限不足"

# 检查Normal OU中的账户数量
MEMBER_COUNT=$(aws organizations list-accounts-for-parent --parent-id $NORMAL_OU_ID \
  --query 'length(Accounts)' --output text)

echo "Normal OU成员账户数: $MEMBER_COUNT" | tee -a $LOG_FILE
echo "StackSet实例应该部署到 $MEMBER_COUNT 个账户" | tee -a $LOG_FILE
```

### 6. 测试CloudFront监控功能
```bash
echo "=== 测试CloudFront监控功能 ===" | tee -a $LOG_FILE

# 检查是否有CloudFront分发
echo "--- 当前CloudFront分发 ---" | tee -a $LOG_FILE
DISTRIBUTIONS=$(aws cloudfront list-distributions --region us-east-1 \
  --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status}' \
  --output table 2>/dev/null || echo "无CloudFront分发或权限不足")

echo "$DISTRIBUTIONS" | tee -a $LOG_FILE

# 检查CloudWatch指标
echo "--- CloudFront CloudWatch指标 ---" | tee -a $LOG_FILE
aws cloudwatch list-metrics --namespace AWS/CloudFront --region us-east-1 \
  --query 'Metrics[0:5].{MetricName:MetricName,Dimensions:Dimensions}' \
  --output table | tee -a $LOG_FILE
```

### 7. 验证Telegram集成配置
```bash
echo "=== 验证Telegram集成配置 ===" | tee -a $LOG_FILE

# 检查Lambda函数的环境变量
if [ -n "$ALERT_LAMBDA_NAME" ]; then
  echo "--- CloudFront告警Lambda环境变量 ---" | tee -a $LOG_FILE
  aws lambda get-function-configuration --function-name $ALERT_LAMBDA_NAME --region $REGION \
    --query 'Environment.Variables' | tee -a $LOG_FILE
fi

# 注意：实际的Telegram Bot Token应该通过AWS Systems Manager Parameter Store或Secrets Manager管理
echo "ℹ️  Telegram Bot配置需要有效的Bot Token和Group ID" | tee -a $LOG_FILE
echo "当前配置的Group ID: $TELEGRAM_GROUP_ID" | tee -a $LOG_FILE
```

### 8. 检查Lambda执行日志
```bash
echo "=== 检查Lambda执行日志 ===" | tee -a $LOG_FILE

# 检查CloudFront告警函数日志
ALERT_LOG_GROUP="/aws/lambda/${PAYER_NAME}-CloudFront-Alert"
LATEST_ALERT_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$ALERT_LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --limit 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>/dev/null || echo "无日志流")

if [ "$LATEST_ALERT_STREAM" != "无日志流" ]; then
  echo "CloudFront告警函数最新日志:" | tee -a $LOG_FILE
  aws logs get-log-events \
    --log-group-name "$ALERT_LOG_GROUP" \
    --log-stream-name "$LATEST_ALERT_STREAM" \
    --limit 10 \
    --query 'events[].message' \
    --output text | tee -a $LOG_FILE
else
  echo "ℹ️  暂无CloudFront告警函数执行日志（等待告警触发）" | tee -a $LOG_FILE
fi

# 检查OAM设置函数日志
OAM_LOG_GROUP="/aws/lambda/${PAYER_NAME}-OAM-Setup"
LATEST_OAM_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$OAM_LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --limit 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>/dev/null || echo "无日志流")

if [ "$LATEST_OAM_STREAM" != "无日志流" ]; then
  echo "OAM设置函数最新日志:" | tee -a $LOG_FILE
  aws logs get-log-events \
    --log-group-name "$OAM_LOG_GROUP" \
    --log-stream-name "$LATEST_OAM_STREAM" \
    --limit 10 \
    --query 'events[].message' \
    --output text | tee -a $LOG_FILE
else
  echo "ℹ️  暂无OAM设置函数执行日志" | tee -a $LOG_FILE
fi
```

## 成功标准检查清单

完成以下所有检查项表示模组7测试成功：

### OAM基础设施检查
- [ ] OAM Sink创建成功并获得ARN
- [ ] OAM Sink配置正确，支持CloudWatch指标
- [ ] StackSet创建成功并处于ACTIVE状态

### CloudFront监控检查
- [ ] CloudWatch告警创建成功
- [ ] 告警阈值设置为指定值（如100MB）
- [ ] 告警状态正常（OK或INSUFFICIENT_DATA）

### Lambda函数检查
- [ ] CloudFront告警Lambda函数创建成功
- [ ] OAM设置Lambda函数创建成功
- [ ] Lambda函数环境变量配置正确
- [ ] Telegram集成配置正确

### StackSet部署检查
- [ ] StackSet成功部署到Normal OU
- [ ] StackSet实例状态为SUCCESS或CURRENT
- [ ] 自动部署配置已启用
- [ ] OAM Links在成员账户中创建成功（如有成员账户）

### 监控系统检查
- [ ] CloudFormation栈状态为CREATE_COMPLETE
- [ ] 无资源创建失败
- [ ] 所有输出值正确生成

## 故障排除

### 常见问题1: OAM权限不足
**症状**: OAM Sink创建失败或无法访问
**解决方案**:
```bash
# 检查OAM服务权限
aws sts get-caller-identity
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names oam:CreateSink \
  --resource-arns "*"

# 检查区域支持（OAM仅在特定区域可用）
aws oam list-sinks --region us-east-1
aws oam list-sinks --region us-west-2
```

### 常见问题2: StackSet权限错误
**症状**: StackSet创建失败或部署失败
**解决方案**:
```bash
# 检查StackSets信任访问
aws organizations list-aws-service-access-for-organization

# 重新启用信任访问
aws organizations enable-aws-service-access \
  --service-principal stacksets.cloudformation.amazonaws.com

# 检查StackSet IAM角色
aws iam get-role --role-name AWSCloudFormationStackSetExecutionRole 2>/dev/null
```

### 常见问题3: CloudWatch告警配置错误
**症状**: 告警创建失败或无法触发
**解决方案**:
```bash
# 检查CloudWatch指标是否存在
aws cloudwatch list-metrics --namespace AWS/CloudFront

# 检查告警配置
aws cloudwatch describe-alarms --alarm-names "$CLOUDFRONT_ALARM_NAME"

# 测试SNS通知
aws sns publish \
  --topic-arn "arn:aws:sns:us-east-1:123456789012:cloudfront-alerts" \
  --message "Test message"
```

### 常见问题4: Telegram集成失败
**症状**: Telegram通知不工作
**解决方案**:
```bash
# 检查Lambda函数环境变量
aws lambda get-function-configuration --function-name "${PAYER_NAME}-CloudFront-Alert"

# 检查Telegram Bot Token配置（应通过Parameter Store）
aws ssm get-parameter --name "/telegram/bot/token" --with-decryption

# 测试Telegram连接
curl -X GET "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getMe"
```

### 常见问题5: 成员账户StackSet部署失败
**症状**: StackSet实例显示FAILED状态
**解决方案**:
```bash
# 检查失败的实例详情
aws cloudformation describe-stack-instance \
  --stack-set-name "$STACKSET_NAME" \
  --stack-instance-account <ACCOUNT_ID> \
  --stack-instance-region us-east-1

# 检查成员账户权限
# 成员账户需要有AWSCloudFormationStackSetExecutionRole

# 重试部署
aws cloudformation create-stack-instances \
  --stack-set-name "$STACKSET_NAME" \
  --deployment-targets OrganizationalUnitIds="$NORMAL_OU_ID" \
  --regions "us-east-1"
```

## 功能测试

### 测试CloudFront告警
如果您有CloudFront分发，可以测试告警功能：

```bash
echo "=== CloudFront告警功能测试 ===" | tee -a $LOG_FILE

read -p "是否要测试CloudFront告警功能？(需要有CloudFront分发) (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # 手动触发告警状态
  echo "模拟CloudFront流量超过阈值的告警..." | tee -a $LOG_FILE
  
  # 更改告警阈值以触发告警（仅用于测试）
  aws cloudwatch put-metric-alarm \
    --alarm-name "$CLOUDFRONT_ALARM_NAME" \
    --alarm-description "Test CloudFront bandwidth usage" \
    --threshold 1 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --metric-name BytesDownloaded \
    --namespace AWS/CloudFront \
    --statistic Sum \
    --unit Bytes \
    --region us-east-1
  
  echo "告警阈值已临时调整为1字节用于测试" | tee -a $LOG_FILE
  echo "请监控Telegram通知和Lambda函数日志" | tee -a $LOG_FILE
  echo "测试完成后记得恢复原始阈值" | tee -a $LOG_FILE
else
  echo "跳过CloudFront告警测试" | tee -a $LOG_FILE
fi
```

## 清理步骤

如果需要清理模组7资源：

```bash
echo "开始清理模组7资源..." | tee -a $LOG_FILE

# 删除StackSet实例
echo "删除StackSet实例..." | tee -a $LOG_FILE
aws cloudformation delete-stack-instances \
  --stack-set-name "$STACKSET_NAME" \
  --deployment-targets OrganizationalUnitIds="$NORMAL_OU_ID" \
  --regions "$REGION" \
  --retain-stacks false \
  --region "$REGION"

# 等待实例删除完成
echo "等待StackSet实例删除完成..." | tee -a $LOG_FILE
sleep 120

# 删除StackSet
echo "删除StackSet..." | tee -a $LOG_FILE
aws cloudformation delete-stack-set \
  --stack-set-name "$STACKSET_NAME" \
  --region "$REGION"

# 删除主CloudFormation栈
aws cloudformation delete-stack \
  --stack-name $MODULE7_STACK_NAME \
  --region $REGION

echo "等待主栈删除完成..." | tee -a $LOG_FILE

# 监控删除进度
aws cloudformation wait stack-delete-complete \
  --stack-name $MODULE7_STACK_NAME \
  --region $REGION

echo "✅ 模组7资源清理完成" | tee -a $LOG_FILE
```

## 下一步

模组7测试成功后：
1. CloudFront跨账户监控系统现已激活
2. 新加入Normal OU的账户将自动获得监控能力
3. 系统将监控所有CloudFront分发的流量

```bash
# 保存关键变量供参考
echo "export MONITORING_SINK_ARN='$MONITORING_SINK_ARN'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export CLOUDFRONT_ALARM_NAME='$CLOUDFRONT_ALARM_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export STACKSET_NAME='$STACKSET_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export MODULE7_STACK_NAME='$MODULE7_STACK_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

echo "✅ 模组7测试完成，变量已保存" | tee -a $LOG_FILE
echo "🎯 所有7个模组测试完成！" | tee -a $LOG_FILE
echo "🚀 AWS Payer自动化系统现已全面部署" | tee -a $LOG_FILE

# 系统功能总结
cat << 'EOF' | tee -a $LOG_FILE

=== AWS Payer自动化系统功能总结 ===

✅ 模组1: OU和SCP策略管理
✅ 模组2: BillingConductor和账户管理  
✅ 模组3: Pro forma CUR导出
✅ 模组4: RISP标准CUR导出
✅ 模组5: Athena数据分析环境
✅ 模组6: 账户自动移动系统
✅ 模组7: CloudFront跨账户监控

系统现在具备：
- 自动账户管理和OU结构
- 双重成本报告（pro forma + 标准定价）
- Athena数据分析能力
- 自动账户移动到适当OU
- CloudFront流量监控和告警
- Telegram实时通知

EOF

echo "📚 详细使用指南请参考各模组的README文档" | tee -a $LOG_FILE
```