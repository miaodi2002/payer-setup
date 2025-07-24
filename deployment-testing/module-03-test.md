# 模组3测试: Pro forma CUR Export

## 测试状态
- ⏸️ **测试状态**: 未开始
- 📅 **预计时间**: 10-15分钟
- 🎯 **成功标准**: 创建S3存储桶和Pro forma CUR导出配置

## 模组概述

**功能**: 创建Pro forma CUR (Cost and Usage Report) 导出
**创建资源**:
- S3存储桶用于CUR数据存储
- Legacy CUR导出（使用BillingGroup的pro forma定价）
- S3存储桶策略和权限配置

## 前置条件检查

### 1. 验证模组2依赖
```bash
# 加载之前模组的输出变量
if [ -f "/Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh" ]; then
  source /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
  echo "✅ 已加载之前的模组变量"
  echo "BillingGroup ARN: $BILLING_GROUP_ARN"
else
  echo "❌ 未找到之前模组的变量，请先完成模组2测试"
  exit 1
fi

# 验证BillingGroup ARN存在
if [ -z "$BILLING_GROUP_ARN" ]; then
  echo "❌ BillingGroup ARN未设置，请先完成模组2测试"
  exit 1
fi
```

### 2. 验证区域要求
```bash
# CUR导出只能在us-east-1区域创建
export REGION="us-east-1"
CURRENT_REGION=$(aws configure get region)

if [ "$CURRENT_REGION" != "$REGION" ]; then
  echo "⚠️  当前AWS CLI区域: $CURRENT_REGION"
  echo "ℹ️  CUR导出需要在us-east-1区域"
  echo "设置临时区域..." 
  export AWS_DEFAULT_REGION=$REGION
fi

echo "✅ 区域设置确认: $REGION"
```

### 3. 验证CUR服务权限
```bash
# 检查CUR权限
aws cur describe-report-definitions --region $REGION > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ CUR服务权限正常"
else
  echo "⚠️  CUR服务权限可能有问题，但继续测试"
fi

# 检查S3权限
aws s3api list-buckets > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ S3服务权限正常"
else
  echo "❌ S3服务权限有问题"
  exit 1
fi
```

## 部署步骤

### 步骤1: 设置环境变量
```bash
# 设置基础变量
export TIMESTAMP=$(date +%s)
export STACK_PREFIX="payer"
export MODULE3_STACK_NAME="${STACK_PREFIX}-cur-proforma-${TIMESTAMP}"

# 生成S3存储桶名称（全局唯一）
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
export EXPECTED_BUCKET_NAME="bip-cur-${MASTER_ACCOUNT_ID}"

# 验证变量
echo "=== 模组3环境变量 ==="
echo "Stack Name: $MODULE3_STACK_NAME"
echo "Expected Bucket Name: $EXPECTED_BUCKET_NAME"
echo "BillingGroup ARN: $BILLING_GROUP_ARN"
echo "Region: $REGION"
```

### 步骤2: 验证CloudFormation模板
```bash
# 切换到项目目录
cd /Users/di.miao/Work/payer-setup/aws-payer-automation

# 验证模板语法
aws cloudformation validate-template \
  --template-body file://templates/03-cur-proforma/cur_export_proforma.yaml \
  --region $REGION

echo "✅ 模板验证通过"
```

### 步骤3: 创建日志文件
```bash
# 创建测试日志
export LOG_FILE="/Users/di.miao/Work/payer-setup/deployment-testing/logs/module-03-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

echo "$(date): 开始模组3部署测试" | tee -a $LOG_FILE
echo "BillingGroup ARN: $BILLING_GROUP_ARN" | tee -a $LOG_FILE
```

### 步骤4: 部署CloudFormation栈
```bash
# 部署栈
echo "开始部署模组3..." | tee -a $LOG_FILE

aws cloudformation create-stack \
  --stack-name $MODULE3_STACK_NAME \
  --template-body file://templates/03-cur-proforma/cur_export_proforma.yaml \
  --parameters ParameterKey=BillingGroupArn,ParameterValue="$BILLING_GROUP_ARN" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=TestModule,Value=Module3 Key=TestRun,Value=$TIMESTAMP

echo "栈创建请求已提交: $MODULE3_STACK_NAME" | tee -a $LOG_FILE
```

### 步骤5: 监控部署进度
```bash
# 监控栈创建状态
echo "监控栈部署状态..." | tee -a $LOG_FILE

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name $MODULE3_STACK_NAME \
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
        --stack-name $MODULE3_STACK_NAME \
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
export PROFORMA_BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE3_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

export PROFORMA_REPORT_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE3_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ReportName`].OutputValue' \
  --output text)

echo "Pro forma Bucket名称: $PROFORMA_BUCKET_NAME" | tee -a $LOG_FILE
echo "Pro forma Report名称: $PROFORMA_REPORT_NAME" | tee -a $LOG_FILE
```

## 部署验证检查

### 1. 验证S3存储桶创建
```bash
echo "=== 验证S3存储桶创建 ===" | tee -a $LOG_FILE

# 检查存储桶是否存在
aws s3api head-bucket --bucket $PROFORMA_BUCKET_NAME --region $REGION 2>/dev/null
if [ $? -eq 0 ]; then
  echo "✅ S3存储桶创建成功: $PROFORMA_BUCKET_NAME" | tee -a $LOG_FILE
else
  echo "❌ S3存储桶不存在或无法访问: $PROFORMA_BUCKET_NAME" | tee -a $LOG_FILE
fi

# 检查存储桶配置
echo "--- 存储桶基本信息 ---" | tee -a $LOG_FILE
aws s3api get-bucket-location --bucket $PROFORMA_BUCKET_NAME | tee -a $LOG_FILE

# 检查存储桶版本控制
echo "--- 版本控制状态 ---" | tee -a $LOG_FILE
aws s3api get-bucket-versioning --bucket $PROFORMA_BUCKET_NAME | tee -a $LOG_FILE

# 检查公共访问阻止
echo "--- 公共访问阻止配置 ---" | tee -a $LOG_FILE
aws s3api get-public-access-block --bucket $PROFORMA_BUCKET_NAME | tee -a $LOG_FILE
```

### 2. 验证存储桶策略
```bash
echo "=== 验证S3存储桶策略 ===" | tee -a $LOG_FILE

# 获取存储桶策略
aws s3api get-bucket-policy --bucket $PROFORMA_BUCKET_NAME \
  --query 'Policy' --output text > /tmp/bucket_policy.json 2>/dev/null

if [ $? -eq 0 ]; then
  echo "✅ 存储桶策略已配置" | tee -a $LOG_FILE
  echo "--- 策略内容 ---" | tee -a $LOG_FILE
  cat /tmp/bucket_policy.json | jq . 2>/dev/null | tee -a $LOG_FILE || cat /tmp/bucket_policy.json | tee -a $LOG_FILE
else
  echo "⚠️  未找到存储桶策略或获取失败" | tee -a $LOG_FILE
fi

rm -f /tmp/bucket_policy.json
```

### 3. 验证CUR报告配置
```bash
echo "=== 验证CUR报告配置 ===" | tee -a $LOG_FILE

# 列出所有CUR报告定义
echo "--- 所有CUR报告 ---" | tee -a $LOG_FILE
aws cur describe-report-definitions --region $REGION \
  --query 'ReportDefinitions[].{Name:ReportName,S3Bucket:S3Bucket,Status:RefreshClosedReports}' \
  --output table | tee -a $LOG_FILE

# 查找我们创建的报告
CUR_REPORT_EXISTS=$(aws cur describe-report-definitions --region $REGION \
  --query "ReportDefinitions[?ReportName=='$PROFORMA_REPORT_NAME'].ReportName" \
  --output text)

if [ "$CUR_REPORT_EXISTS" = "$PROFORMA_REPORT_NAME" ]; then
  echo "✅ CUR报告定义创建成功: $PROFORMA_REPORT_NAME" | tee -a $LOG_FILE
  
  # 获取报告详细信息
  echo "--- Pro forma CUR报告详细信息 ---" | tee -a $LOG_FILE
  aws cur describe-report-definitions --region $REGION \
    --query "ReportDefinitions[?ReportName=='$PROFORMA_REPORT_NAME']" \
    --output table | tee -a $LOG_FILE
else
  echo "❌ 未找到CUR报告定义: $PROFORMA_REPORT_NAME" | tee -a $LOG_FILE
fi
```

### 4. 验证Lambda函数执行
```bash
echo "=== 验证Lambda函数执行 ===" | tee -a $LOG_FILE

# 检查Lambda函数日志
LAMBDA_FUNCTION_NAME="CreateCURExport"
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
    --limit 15 \
    --query 'events[].message' \
    --output text | tee -a $LOG_FILE
else
  echo "⚠️  未找到Lambda执行日志" | tee -a $LOG_FILE
fi
```

### 5. 检查CUR数据生成状态
```bash
echo "=== 检查CUR数据生成状态 ===" | tee -a $LOG_FILE

# 检查S3存储桶中的对象
echo "--- 存储桶内容 ---" | tee -a $LOG_FILE
aws s3 ls s3://$PROFORMA_BUCKET_NAME/ --recursive | head -10 | tee -a $LOG_FILE

OBJECT_COUNT=$(aws s3 ls s3://$PROFORMA_BUCKET_NAME/ --recursive | wc -l)
echo "存储桶中的对象数量: $OBJECT_COUNT" | tee -a $LOG_FILE

if [ $OBJECT_COUNT -gt 0 ]; then
  echo "✅ 存储桶中已有对象" | tee -a $LOG_FILE
else
  echo "ℹ️  存储桶为空 (CUR数据可能需要24小时生成)" | tee -a $LOG_FILE
fi
```

## 成功标准检查清单

完成以下所有检查项表示模组3测试成功：

### S3存储桶检查
- [ ] S3存储桶创建成功并可访问
- [ ] 存储桶版本控制已启用
- [ ] 公共访问阻止已配置
- [ ] 存储桶策略正确配置（允许AWS Billing访问）

### CUR报告检查
- [ ] Pro forma CUR报告定义创建成功
- [ ] CUR报告使用指定的BillingGroup
- [ ] CUR报告配置为Legacy格式
- [ ] CUR报告指向正确的S3存储桶

### 系统功能检查
- [ ] CloudFormation栈状态为CREATE_COMPLETE
- [ ] 无资源创建失败
- [ ] Lambda函数执行无致命错误
- [ ] 所有输出值正确生成

## 故障排除

### 常见问题1: S3存储桶名称冲突
**症状**: 存储桶创建失败，名称已存在
**解决方案**:
```bash
# 检查存储桶是否已存在
aws s3api head-bucket --bucket $PROFORMA_BUCKET_NAME 2>&1

# 如果存储桶属于其他账户，Lambda会生成新名称
# 检查实际创建的存储桶名称
aws cloudformation describe-stacks \
  --stack-name $MODULE3_STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text
```

### 常见问题2: CUR报告创建失败
**症状**: Lambda执行失败，CUR创建错误
**解决方案**:
```bash
# 检查是否已存在同名报告
aws cur describe-report-definitions --region $REGION \
  --query 'ReportDefinitions[].ReportName' \
  --output table

# 检查BillingGroup是否有效
aws billingconductor get-billing-group --arn $BILLING_GROUP_ARN --region us-east-1
```

### 常见问题3: 存储桶策略权限错误
**症状**: 存储桶策略配置失败
**解决方案**:
```bash
# 手动检查存储桶策略
aws s3api get-bucket-policy --bucket $PROFORMA_BUCKET_NAME

# 验证Master Account ID是否正确
echo "Master Account ID: $MASTER_ACCOUNT_ID"
aws organizations describe-organization --query 'Organization.MasterAccountId'
```

### 常见问题4: 区域限制问题
**症状**: 在非us-east-1区域无法创建CUR
**解决方案**:
```bash
# 确认当前区域
echo "Current Region: $AWS_DEFAULT_REGION"

# 切换到正确区域
export AWS_DEFAULT_REGION=us-east-1

# 重新验证权限
aws cur describe-report-definitions --region us-east-1
```

## 清理步骤

如果需要清理模组3资源：

```bash
echo "开始清理模组3资源..." | tee -a $LOG_FILE

# 删除CUR报告定义（如果存在）
if [ -n "$PROFORMA_REPORT_NAME" ]; then
  aws cur delete-report-definition \
    --report-name $PROFORMA_REPORT_NAME \
    --region $REGION 2>/dev/null || echo "CUR报告删除失败或不存在"
fi

# 清空S3存储桶（如果需要）
if [ -n "$PROFORMA_BUCKET_NAME" ]; then
  echo "清空S3存储桶: $PROFORMA_BUCKET_NAME" | tee -a $LOG_FILE
  aws s3 rm s3://$PROFORMA_BUCKET_NAME/ --recursive 2>/dev/null || echo "存储桶清空失败或为空"
fi

# 删除CloudFormation栈
aws cloudformation delete-stack \
  --stack-name $MODULE3_STACK_NAME \
  --region $REGION

echo "等待栈删除完成..." | tee -a $LOG_FILE

# 监控删除进度
aws cloudformation wait stack-delete-complete \
  --stack-name $MODULE3_STACK_NAME \
  --region $REGION

echo "✅ 模组3资源清理完成" | tee -a $LOG_FILE
```

## 下一步

模组3测试成功后：
1. 保存存储桶和报告名称变量（模组5需要使用）
2. 可以并行执行模组4测试
3. 等待24小时查看CUR数据生成情况

```bash
# 保存关键变量供后续模组使用
echo "export PROFORMA_BUCKET_NAME='$PROFORMA_BUCKET_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export PROFORMA_REPORT_NAME='$PROFORMA_REPORT_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export MODULE3_STACK_NAME='$MODULE3_STACK_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

echo "✅ 模组3测试完成，变量已保存" | tee -a $LOG_FILE
echo "🎯 下一步: 可以并行执行模组4 (RISP CUR) 测试" | tee -a $LOG_FILE
echo "ℹ️  CUR数据将在24小时内开始生成" | tee -a $LOG_FILE
```