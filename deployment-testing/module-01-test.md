# 模组1测试: OU和SCP设置

## 测试状态
- ⏸️ **测试状态**: 未开始
- 📅 **预计时间**: 10-15分钟
- 🎯 **成功标准**: 创建3个OU并成功附加SCP策略

## 模组概述

**功能**: 创建AWS Organizations的组织单元(OU)结构和服务控制策略(SCP)
**创建资源**:
- 3个组织单元: Free, Block, Normal
- 7个SCP策略（防止预留实例购买、限制实例大小等）
- 自动将SCP附加到相应的OU

## 前置条件检查

### 1. 验证AWS Organizations状态
```bash
# 检查Organizations是否启用
aws organizations describe-organization

# 确认SCP功能已启用
aws organizations describe-organization | grep -i "\"AllFeaturesEnabled\""
# 应该显示: "FeatureSet": "ALL"

# 获取Root ID
export ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Root ID: $ROOT_ID"
```

### 2. 检查现有OU结构
```bash
# 列出现有的OU
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID

# 检查是否已存在同名OU (如果存在，可能需要手动清理)
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID \
  --query 'OrganizationalUnits[?Name==`Free` || Name==`Block` || Name==`Normal`]'
```

### 3. 检查SCP权限
```bash
# 列出现有的SCP策略
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# 检查SCP启用状态
aws organizations describe-organization | grep -i policy
```

## 部署步骤

### 步骤1: 设置环境变量
```bash
# 设置基础变量
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"
export MODULE1_STACK_NAME="${STACK_PREFIX}-ou-scp-${TIMESTAMP}"

# 验证变量
echo "=== 模组1环境变量 ==="
echo "Stack Name: $MODULE1_STACK_NAME"
echo "Root ID: $ROOT_ID"
echo "Region: $REGION"
```

### 步骤2: 验证CloudFormation模板
```bash
# 切换到项目目录
cd /Users/di.miao/Work/payer-setup/aws-payer-automation

# 验证模板语法
aws cloudformation validate-template \
  --template-body file://templates/01-ou-scp/auto_SCP_1.yaml \
  --region $REGION

echo "✅ 模板验证通过"
```

### 步骤3: 创建日志文件
```bash
# 创建测试日志
export LOG_FILE="/Users/di.miao/Work/payer-setup/deployment-testing/logs/module-01-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

echo "$(date): 开始模组1部署测试" | tee -a $LOG_FILE
```

### 步骤4: 部署CloudFormation栈
```bash
# 部署栈
echo "开始部署模组1..." | tee -a $LOG_FILE

aws cloudformation create-stack \
  --stack-name $MODULE1_STACK_NAME \
  --template-body file://templates/01-ou-scp/auto_SCP_1.yaml \
  --parameters ParameterKey=RootId,ParameterValue=$ROOT_ID \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=TestModule,Value=Module1 Key=TestRun,Value=$TIMESTAMP

echo "栈创建请求已提交: $MODULE1_STACK_NAME" | tee -a $LOG_FILE
```

### 步骤5: 监控部署进度
```bash
# 监控栈创建状态
echo "监控栈部署状态..." | tee -a $LOG_FILE

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name $MODULE1_STACK_NAME \
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
        --stack-name $MODULE1_STACK_NAME \
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

## 部署验证检查

### 1. 验证OU创建
```bash
echo "=== 验证OU创建 ===" | tee -a $LOG_FILE

# 获取栈输出
FREE_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name $MODULE1_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`FreeOUId`].OutputValue' \
  --output text)

BLOCK_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name $MODULE1_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`BlockOUId`].OutputValue' \
  --output text)

NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name $MODULE1_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text)

echo "Free OU ID: $FREE_OU_ID" | tee -a $LOG_FILE
echo "Block OU ID: $BLOCK_OU_ID" | tee -a $LOG_FILE
echo "Normal OU ID: $NORMAL_OU_ID" | tee -a $LOG_FILE

# 验证OU存在
for OU_ID in $FREE_OU_ID $BLOCK_OU_ID $NORMAL_OU_ID; do
  OU_NAME=$(aws organizations describe-organizational-unit \
    --organizational-unit-id $OU_ID \
    --query 'OrganizationalUnit.Name' \
    --output text 2>/dev/null || echo "ERROR")
  
  if [ "$OU_NAME" != "ERROR" ]; then
    echo "✅ OU验证成功: $OU_NAME ($OU_ID)" | tee -a $LOG_FILE
  else
    echo "❌ OU验证失败: $OU_ID" | tee -a $LOG_FILE
  fi
done
```

### 2. 验证SCP策略创建和附加
```bash
echo "=== 验证SCP策略 ===" | tee -a $LOG_FILE

# 列出所有SCP策略
aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[?contains(Name, `SCP_`) || contains(Name, `Prevent`)].{Name:Name,Id:Id}' \
  --output table | tee -a $LOG_FILE

# 检查每个OU附加的策略
for OU_ID in $FREE_OU_ID $BLOCK_OU_ID $NORMAL_OU_ID; do
  OU_NAME=$(aws organizations describe-organizational-unit \
    --organizational-unit-id $OU_ID \
    --query 'OrganizationalUnit.Name' \
    --output text)
  
  echo "--- $OU_NAME OU 的附加策略 ---" | tee -a $LOG_FILE
  aws organizations list-policies-for-target \
    --target-id $OU_ID \
    --filter SERVICE_CONTROL_POLICY \
    --query 'Policies[].Name' \
    --output table | tee -a $LOG_FILE
done
```

### 3. 验证Lambda函数执行
```bash
echo "=== 验证Lambda函数 ===" | tee -a $LOG_FILE

# 检查Lambda函数日志
LAMBDA_FUNCTION_NAME="AttachSCPToOU"
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
  --query 'logGroups[0].logGroupName' \
  --output text | tee -a $LOG_FILE

# 获取最新日志流
LATEST_LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
  --order-by LastEventTime \
  --descending \
  --limit 1 \
  --query 'logStreams[0].logStreamName' \
  --output text 2>/dev/null || echo "无日志流")

if [ "$LATEST_LOG_STREAM" != "无日志流" ]; then
  echo "最新Lambda执行日志:" | tee -a $LOG_FILE
  aws logs get-log-events \
    --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
    --log-stream-name "$LATEST_LOG_STREAM" \
    --limit 10 \
    --query 'events[].message' \
    --output text | tee -a $LOG_FILE
fi
```

## 成功标准检查清单

完成以下所有检查项表示模组1测试成功：

### OU创建检查
- [ ] Free OU 创建成功并可访问
- [ ] Block OU 创建成功并可访问  
- [ ] Normal OU 创建成功并可访问
- [ ] 所有OU都在Root下正确创建

### SCP策略检查
- [ ] 7个SCP策略全部创建成功
- [ ] PreventInstanceType策略正确附加到Free OU
- [ ] PreventReservedInstance策略正确附加到Normal OU
- [ ] PreventRootUser策略正确附加到所有OU
- [ ] 其他SCP策略按预期附加

### 系统功能检查
- [ ] CloudFormation栈状态为CREATE_COMPLETE
- [ ] 无资源创建失败
- [ ] Lambda函数执行无错误
- [ ] 所有输出值正确生成

## 故障排除

### 常见问题1: SCP功能未启用
**症状**: Organizations不支持SCP策略
**解决方案**:
```bash
# 检查Organizations功能集
aws organizations describe-organization | grep FeatureSet

# 如果显示"CONSOLIDATED_BILLING"，需要启用全部功能
aws organizations enable-all-features
```

### 常见问题2: Lambda函数权限错误
**症状**: SCP附加失败，权限被拒绝
**解决方案**:
```bash
# 检查当前用户权限
aws sts get-caller-identity

# 验证Organizations管理员权限
aws iam list-attached-user-policies --user-name $(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)
```

### 常见问题3: OU名称冲突
**症状**: OU创建失败，名称已存在
**解决方案**:
```bash
# 列出现有OU
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID

# 手动删除冲突的OU（注意：OU必须为空才能删除）
# aws organizations delete-organizational-unit --organizational-unit-id ou-xxxx
```

## 清理步骤

如果需要清理模组1资源：

```bash
echo "开始清理模组1资源..." | tee -a $LOG_FILE

# 删除CloudFormation栈
aws cloudformation delete-stack \
  --stack-name $MODULE1_STACK_NAME \
  --region $REGION

echo "等待栈删除完成..." | tee -a $LOG_FILE

# 监控删除进度
aws cloudformation wait stack-delete-complete \
  --stack-name $MODULE1_STACK_NAME \
  --region $REGION

echo "✅ 模组1资源清理完成" | tee -a $LOG_FILE
```

## 下一步

模组1测试成功后：
1. 保存 `NORMAL_OU_ID` 环境变量（模组6和7会用到）
2. 继续执行模组2测试
3. 将成功的配置记录到测试日志中

```bash
# 保存关键变量供后续模组使用
echo "export NORMAL_OU_ID=$NORMAL_OU_ID" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export FREE_OU_ID=$FREE_OU_ID" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export BLOCK_OU_ID=$BLOCK_OU_ID" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export MODULE1_STACK_NAME=$MODULE1_STACK_NAME" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

echo "✅ 模组1测试完成，变量已保存" | tee -a $LOG_FILE
```