# 模组4测试: RISP CUR Export

## 测试状态
- ⏸️ **测试状态**: 未开始
- 📅 **预计时间**: 10-15分钟
- 🎯 **成功标准**: 创建独立的S3存储桶和RISP标准定价CUR导出

## 模组概述

**功能**: 创建RISP (标准定价) CUR (Cost and Usage Report) 导出
**创建资源**:
- 独立的S3存储桶用于RISP CUR数据存储
- 标准Legacy CUR导出（不使用pro forma定价）
- 提供标准AWS定价数据，用于对比分析

## 前置条件检查

### 1. 验证区域要求（与模组3相同）
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

### 2. 验证基础服务权限
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

# 获取Master Account ID
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
echo "Master Account ID: $MASTER_ACCOUNT_ID"
```

### 3. 验证模组3状态（可选检查）
```bash
# 加载之前模组的输出变量（如果存在）
if [ -f "/Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh" ]; then
  source /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
  echo "✅ 已加载之前的模组变量"
  if [ -n "$PROFORMA_BUCKET_NAME" ]; then
    echo "ℹ️  模组3 Pro forma存储桶: $PROFORMA_BUCKET_NAME"
  fi
else
  echo "ℹ️  未找到之前模组的变量（模组4可以独立测试）"
fi
```

## 部署步骤

### 步骤1: 设置环境变量
```bash
# 设置基础变量
export TIMESTAMP=$(date +%s)
export STACK_PREFIX="payer"
export MODULE4_STACK_NAME="${STACK_PREFIX}-cur-risp-${TIMESTAMP}"

# 生成RISP S3存储桶名称（与Pro forma区分）
export EXPECTED_RISP_BUCKET_NAME="bip-risp-cur-${MASTER_ACCOUNT_ID}"
export EXPECTED_RISP_REPORT_NAME="risp-${MASTER_ACCOUNT_ID}"

# 验证变量
echo "=== 模组4环境变量 ==="
echo "Stack Name: $MODULE4_STACK_NAME"
echo "Expected RISP Bucket Name: $EXPECTED_RISP_BUCKET_NAME"
echo "Expected RISP Report Name: $EXPECTED_RISP_REPORT_NAME"
echo "Region: $REGION"
```

### 步骤2: 验证CloudFormation模板
```bash
# 切换到项目目录
cd /Users/di.miao/Work/payer-setup/aws-payer-automation

# 验证模板语法
aws cloudformation validate-template \
  --template-body file://templates/04-cur-risp/cur_export_risp.yaml \
  --region $REGION

echo "✅ 模板验证通过"
```

### 步骤3: 创建日志文件
```bash
# 创建测试日志
export LOG_FILE="/Users/di.miao/Work/payer-setup/deployment-testing/logs/module-04-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

echo "$(date): 开始模组4部署测试" | tee -a $LOG_FILE
echo "RISP Bucket: $EXPECTED_RISP_BUCKET_NAME" | tee -a $LOG_FILE
echo "RISP Report: $EXPECTED_RISP_REPORT_NAME" | tee -a $LOG_FILE
```

### 步骤4: 部署CloudFormation栈
```bash
# 部署栈（模组4不需要参数，完全独立）
echo "开始部署模组4..." | tee -a $LOG_FILE

aws cloudformation create-stack \
  --stack-name $MODULE4_STACK_NAME \
  --template-body file://templates/04-cur-risp/cur_export_risp.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=TestModule,Value=Module4 Key=TestRun,Value=$TIMESTAMP

echo "栈创建请求已提交: $MODULE4_STACK_NAME" | tee -a $LOG_FILE
```

### 步骤5: 监控部署进度
```bash
# 监控栈创建状态
echo "监控栈部署状态..." | tee -a $LOG_FILE

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name $MODULE4_STACK_NAME \
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
        --stack-name $MODULE4_STACK_NAME \
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
export RISP_BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE4_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPBucketName`].OutputValue' \
  --output text)

export RISP_REPORT_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE4_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPReportName`].OutputValue' \
  --output text)

echo "RISP Bucket名称: $RISP_BUCKET_NAME" | tee -a $LOG_FILE
echo "RISP Report名称: $RISP_REPORT_NAME" | tee -a $LOG_FILE
```

## 部署验证检查

### 1. 验证RISP S3存储桶创建
```bash
echo "=== 验证RISP S3存储桶创建 ===" | tee -a $LOG_FILE

# 检查存储桶是否存在
aws s3api head-bucket --bucket $RISP_BUCKET_NAME --region $REGION 2>/dev/null
if [ $? -eq 0 ]; then
  echo "✅ RISP S3存储桶创建成功: $RISP_BUCKET_NAME" | tee -a $LOG_FILE
else
  echo "❌ RISP S3存储桶不存在或无法访问: $RISP_BUCKET_NAME" | tee -a $LOG_FILE
fi

# 检查存储桶配置
echo "--- 存储桶基本信息 ---" | tee -a $LOG_FILE
aws s3api get-bucket-location --bucket $RISP_BUCKET_NAME | tee -a $LOG_FILE

# 检查存储桶版本控制
echo "--- 版本控制状态 ---" | tee -a $LOG_FILE
aws s3api get-bucket-versioning --bucket $RISP_BUCKET_NAME | tee -a $LOG_FILE

# 检查公共访问阻止
echo "--- 公共访问阻止配置 ---" | tee -a $LOG_FILE
aws s3api get-public-access-block --bucket $RISP_BUCKET_NAME | tee -a $LOG_FILE
```

### 2. 验证存储桶策略配置
```bash
echo "=== 验证RISP S3存储桶策略 ===" | tee -a $LOG_FILE

# 获取存储桶策略
aws s3api get-bucket-policy --bucket $RISP_BUCKET_NAME \
  --query 'Policy' --output text > /tmp/risp_bucket_policy.json 2>/dev/null

if [ $? -eq 0 ]; then
  echo "✅ RISP存储桶策略已配置" | tee -a $LOG_FILE
  echo "--- 策略内容 ---" | tee -a $LOG_FILE
  cat /tmp/risp_bucket_policy.json | jq . 2>/dev/null | tee -a $LOG_FILE || cat /tmp/risp_bucket_policy.json | tee -a $LOG_FILE
else
  echo "⚠️  未找到RISP存储桶策略或获取失败" | tee -a $LOG_FILE
fi

rm -f /tmp/risp_bucket_policy.json
```

### 3. 验证RISP CUR报告配置
```bash
echo "=== 验证RISP CUR报告配置 ===" | tee -a $LOG_FILE

# 列出所有CUR报告定义
echo "--- 所有CUR报告（包含新的RISP报告） ---" | tee -a $LOG_FILE
aws cur describe-report-definitions --region $REGION \
  --query 'ReportDefinitions[].{Name:ReportName,S3Bucket:S3Bucket,Status:RefreshClosedReports}' \
  --output table | tee -a $LOG_FILE

# 查找我们创建的RISP报告
CUR_REPORT_EXISTS=$(aws cur describe-report-definitions --region $REGION \
  --query "ReportDefinitions[?ReportName=='$RISP_REPORT_NAME'].ReportName" \
  --output text)

if [ "$CUR_REPORT_EXISTS" = "$RISP_REPORT_NAME" ]; then
  echo "✅ RISP CUR报告定义创建成功: $RISP_REPORT_NAME" | tee -a $LOG_FILE
  
  # 获取RISP报告详细信息
  echo "--- RISP CUR报告详细信息 ---" | tee -a $LOG_FILE
  aws cur describe-report-definitions --region $REGION \
    --query "ReportDefinitions[?ReportName=='$RISP_REPORT_NAME']" \
    --output table | tee -a $LOG_FILE
else
  echo "❌ 未找到RISP CUR报告定义: $RISP_REPORT_NAME" | tee -a $LOG_FILE
fi
```

### 4. 对比Pro forma和RISP CUR配置
```bash
echo "=== 对比Pro forma与RISP CUR配置 ===" | tee -a $LOG_FILE

if [ -n "$PROFORMA_REPORT_NAME" ]; then
  echo "--- 配置对比 ---" | tee -a $LOG_FILE
  echo "Pro forma 报告: $PROFORMA_REPORT_NAME" | tee -a $LOG_FILE
  echo "Pro forma 存储桶: $PROFORMA_BUCKET_NAME" | tee -a $LOG_FILE
  echo "RISP 报告: $RISP_REPORT_NAME" | tee -a $LOG_FILE
  echo "RISP 存储桶: $RISP_BUCKET_NAME" | tee -a $LOG_FILE
  
  # 获取两个报告的具体配置对比
  echo "--- Pro forma vs RISP 详细对比 ---" | tee -a $LOG_FILE
  aws cur describe-report-definitions --region $REGION \
    --query "ReportDefinitions[?ReportName=='$PROFORMA_REPORT_NAME' || ReportName=='$RISP_REPORT_NAME'].{Name:ReportName,Bucket:S3Bucket,Compression:Compression,Format:Format,TimeUnit:TimeUnit}" \
    --output table | tee -a $LOG_FILE
else
  echo "ℹ️  Pro forma配置不可用，跳过对比" | tee -a $LOG_FILE
fi
```

### 5. 验证Lambda函数执行
```bash
echo "=== 验证Lambda函数执行 ===" | tee -a $LOG_FILE

# 检查RISP Lambda函数日志
LAMBDA_FUNCTION_NAME="CreateRISPCURExport"
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

### 6. 检查RISP CUR数据生成状态
```bash
echo "=== 检查RISP CUR数据生成状态 ===" | tee -a $LOG_FILE

# 检查RISP S3存储桶中的对象
echo "--- RISP存储桶内容 ---" | tee -a $LOG_FILE
aws s3 ls s3://$RISP_BUCKET_NAME/ --recursive | head -10 | tee -a $LOG_FILE

RISP_OBJECT_COUNT=$(aws s3 ls s3://$RISP_BUCKET_NAME/ --recursive | wc -l)
echo "RISP存储桶中的对象数量: $RISP_OBJECT_COUNT" | tee -a $LOG_FILE

if [ $RISP_OBJECT_COUNT -gt 0 ]; then
  echo "✅ RISP存储桶中已有对象" | tee -a $LOG_FILE
else
  echo "ℹ️  RISP存储桶为空 (CUR数据可能需要24小时生成)" | tee -a $LOG_FILE
fi
```

## 成功标准检查清单

完成以下所有检查项表示模组4测试成功：

### S3存储桶检查
- [ ] RISP S3存储桶创建成功并可访问
- [ ] 存储桶版本控制已启用
- [ ] 公共访问阻止已配置
- [ ] 存储桶策略正确配置（允许AWS Billing访问）
- [ ] 存储桶名称与Pro forma存储桶不同

### CUR报告检查
- [ ] RISP CUR报告定义创建成功
- [ ] RISP CUR报告使用标准定价（非pro forma）
- [ ] RISP CUR报告配置为Legacy格式
- [ ] RISP CUR报告指向正确的S3存储桶
- [ ] 报告名称包含"risp"标识

### 系统功能检查
- [ ] CloudFormation栈状态为CREATE_COMPLETE
- [ ] 无资源创建失败
- [ ] Lambda函数执行无致命错误
- [ ] 所有输出值正确生成

## 故障排除

### 常见问题1: S3存储桶名称冲突
**症状**: RISP存储桶创建失败，名称已存在
**解决方案**:
```bash
# 检查存储桶是否已存在
aws s3api head-bucket --bucket $RISP_BUCKET_NAME 2>&1

# 检查是否与Pro forma存储桶冲突
if [ "$RISP_BUCKET_NAME" = "$PROFORMA_BUCKET_NAME" ]; then
  echo "❌ 存储桶名称与Pro forma冲突"
fi

# Lambda会自动生成唯一名称，检查实际创建的存储桶
aws cloudformation describe-stacks \
  --stack-name $MODULE4_STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPBucketName`].OutputValue' \
  --output text
```

### 常见问题2: CUR报告名称冲突
**症状**: RISP CUR报告创建失败，名称冲突
**解决方案**:
```bash
# 检查现有CUR报告
aws cur describe-report-definitions --region $REGION \
  --query 'ReportDefinitions[].ReportName' \
  --output table

# 确认RISP报告名称与Pro forma报告不同
if [ "$RISP_REPORT_NAME" = "$PROFORMA_REPORT_NAME" ]; then
  echo "❌ 报告名称与Pro forma冲突"
fi
```

### 常见问题3: Lambda执行权限错误
**症状**: Lambda函数创建CUR失败，权限被拒绝
**解决方案**:
```bash
# 检查当前用户CUR权限
aws cur describe-report-definitions --region $REGION

# 检查IAM角色权限
aws iam get-role-policy \
  --role-name LambdaRISPCURRole \
  --policy-name CURAccess 2>/dev/null || echo "角色或策略不存在"
```

### 常见问题4: 与模组3冲突
**症状**: 资源创建失败，可能与Pro forma模组冲突
**解决方案**:
```bash
# 检查当前所有CUR报告
aws cur describe-report-definitions --region $REGION

# 检查S3存储桶列表
aws s3 ls | grep "bip-"

# 确认模组4的资源命名正确
echo "RISP Bucket: $RISP_BUCKET_NAME"
echo "Pro forma Bucket: $PROFORMA_BUCKET_NAME"
```

## 清理步骤

如果需要清理模组4资源：

```bash
echo "开始清理模组4资源..." | tee -a $LOG_FILE

# 删除RISP CUR报告定义（如果存在）
if [ -n "$RISP_REPORT_NAME" ]; then
  aws cur delete-report-definition \
    --report-name $RISP_REPORT_NAME \
    --region $REGION 2>/dev/null || echo "RISP CUR报告删除失败或不存在"
fi

# 清空RISP S3存储桶（如果需要）
if [ -n "$RISP_BUCKET_NAME" ]; then
  echo "清空RISP S3存储桶: $RISP_BUCKET_NAME" | tee -a $LOG_FILE
  aws s3 rm s3://$RISP_BUCKET_NAME/ --recursive 2>/dev/null || echo "RISP存储桶清空失败或为空"
fi

# 删除CloudFormation栈
aws cloudformation delete-stack \
  --stack-name $MODULE4_STACK_NAME \
  --region $REGION

echo "等待栈删除完成..." | tee -a $LOG_FILE

# 监控删除进度
aws cloudformation wait stack-delete-complete \
  --stack-name $MODULE4_STACK_NAME \
  --region $REGION

echo "✅ 模组4资源清理完成" | tee -a $LOG_FILE
```

## 下一步

模组4测试成功后：
1. 保存RISP存储桶和报告名称变量（模组5需要使用）
2. 确认模组3和4都完成，可以继续模组5测试
3. 等待24小时查看RISP CUR数据生成情况

```bash
# 保存关键变量供后续模组使用
echo "export RISP_BUCKET_NAME='$RISP_BUCKET_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export RISP_REPORT_NAME='$RISP_REPORT_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export MODULE4_STACK_NAME='$MODULE4_STACK_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

echo "✅ 模组4测试完成，变量已保存" | tee -a $LOG_FILE
echo "🎯 下一步: 等待模组3完成后，继续模组5 (Athena环境) 测试" | tee -a $LOG_FILE
echo "ℹ️  RISP CUR数据将在24小时内开始生成" | tee -a $LOG_FILE

# 检查是否可以继续模组5
if [ -n "$PROFORMA_BUCKET_NAME" ] && [ -n "$RISP_BUCKET_NAME" ]; then
  echo "✅ 模组3和4都已完成，可以继续模组5测试" | tee -a $LOG_FILE
else
  echo "⏳ 等待模组3完成后再进行模组5测试" | tee -a $LOG_FILE
fi
```