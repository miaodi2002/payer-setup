# 模组5测试: Athena环境设置

## 测试状态
- ⏸️ **测试状态**: 未开始
- 📅 **预计时间**: 15-20分钟
- 🎯 **成功标准**: 创建Athena数据库、Crawler和Lambda函数，处理CUR数据分析

## 模组概述

**功能**: 设置统一的Athena环境管理CUR数据
**创建资源**:
- 两个独立的Glue Database分别管理Pro forma和RISP CUR数据表
- Pro forma和RISP CUR的Glue Crawler
- Lambda函数处理自动化数据发现
- S3事件通知自动触发数据更新
- 状态表跟踪CUR数据生成状态

## 前置条件检查

### 1. 验证模组3和4的依赖
```bash
# 加载之前模组的输出变量
if [ -f "/Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh" ]; then
  source /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
  echo "✅ 已加载之前的模组变量"
else
  echo "❌ 未找到之前模组的变量，请先完成模组3和4测试"
  exit 1
fi

# 验证必需的变量存在
if [ -z "$PROFORMA_BUCKET_NAME" ] || [ -z "$RISP_BUCKET_NAME" ]; then
  echo "❌ Pro forma或RISP存储桶变量未设置"
  echo "Pro forma Bucket: $PROFORMA_BUCKET_NAME"
  echo "RISP Bucket: $RISP_BUCKET_NAME"
  echo "请先完成模组3和4测试"
  exit 1
fi

if [ -z "$PROFORMA_REPORT_NAME" ] || [ -z "$RISP_REPORT_NAME" ]; then
  echo "❌ Pro forma或RISP报告名称变量未设置"
  echo "Pro forma Report: $PROFORMA_REPORT_NAME"
  echo "RISP Report: $RISP_REPORT_NAME"
  echo "请先完成模组3和4测试"
  exit 1
fi

echo "✅ 模组3和4依赖验证通过"
echo "Pro forma Bucket: $PROFORMA_BUCKET_NAME"
echo "RISP Bucket: $RISP_BUCKET_NAME"
echo "Pro forma Report: $PROFORMA_REPORT_NAME"
echo "RISP Report: $RISP_REPORT_NAME"
```

### 2. 验证AWS Glue服务权限
```bash
# 检查Glue权限
aws glue get-databases --region us-east-1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ AWS Glue服务权限正常"
else
  echo "❌ AWS Glue服务权限有问题"
  exit 1
fi

# 检查Athena权限
aws athena list-work-groups --region us-east-1 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Amazon Athena服务权限正常"
else
  echo "❌ Amazon Athena服务权限有问题"
  exit 1
fi
```

### 3. 验证S3存储桶可访问性
```bash
echo "验证CUR存储桶可访问性..."

# 检查Pro forma存储桶
aws s3 ls s3://$PROFORMA_BUCKET_NAME/ > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Pro forma存储桶可访问: $PROFORMA_BUCKET_NAME"
else
  echo "❌ Pro forma存储桶无法访问: $PROFORMA_BUCKET_NAME"
fi

# 检查RISP存储桶
aws s3 ls s3://$RISP_BUCKET_NAME/ > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ RISP存储桶可访问: $RISP_BUCKET_NAME"
else
  echo "❌ RISP存储桶无法访问: $RISP_BUCKET_NAME"
fi
```

## 部署步骤

### 步骤1: 设置环境变量
```bash
# 设置基础变量
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"
export MODULE5_STACK_NAME="${STACK_PREFIX}-athena-setup-${TIMESTAMP}"

# Athena相关变量
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
export EXPECTED_PROFORMA_DATABASE_NAME="athenacurcfn_${MASTER_ACCOUNT_ID}"
export EXPECTED_RISP_DATABASE_NAME="athenacurcfn_risp_${MASTER_ACCOUNT_ID}"

# 验证变量
echo "=== 模组5环境变量 ==="
echo "Stack Name: $MODULE5_STACK_NAME"
echo "Pro forma Database Name: $EXPECTED_PROFORMA_DATABASE_NAME"
echo "RISP Database Name: $EXPECTED_RISP_DATABASE_NAME"
echo "Pro forma Bucket: $PROFORMA_BUCKET_NAME"
echo "RISP Bucket: $RISP_BUCKET_NAME"
echo "Pro forma Report: $PROFORMA_REPORT_NAME"
echo "RISP Report: $RISP_REPORT_NAME"
echo "Region: $REGION"
```

### 步骤2: 验证CloudFormation模板
```bash
# 切换到项目目录
cd /Users/di.miao/Work/payer-setup/aws-payer-automation

# 验证模板语法
aws cloudformation validate-template \
  --template-body file://templates/05-athena-setup/athena_setup.yaml \
  --region $REGION

echo "✅ 模板验证通过"
```

### 步骤3: 创建日志文件
```bash
# 创建测试日志
export LOG_FILE="/Users/di.miao/Work/payer-setup/deployment-testing/logs/module-05-$(date +%Y%m%d_%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

echo "$(date): 开始模组5部署测试" | tee -a $LOG_FILE
echo "所有参数:" | tee -a $LOG_FILE
echo "  ProformaBucketName: $PROFORMA_BUCKET_NAME" | tee -a $LOG_FILE
echo "  RISPBucketName: $RISP_BUCKET_NAME" | tee -a $LOG_FILE
echo "  ProformaReportName: $PROFORMA_REPORT_NAME" | tee -a $LOG_FILE
echo "  RISPReportName: $RISP_REPORT_NAME" | tee -a $LOG_FILE
```

### 步骤4: 部署CloudFormation栈
```bash
# 部署栈（需要4个参数）
echo "开始部署模组5..." | tee -a $LOG_FILE
echo "⚠️  此模组需要大约15分钟，包括Athena设置和初始爬取" | tee -a $LOG_FILE

aws cloudformation create-stack \
  --stack-name $MODULE5_STACK_NAME \
  --template-body file://templates/05-athena-setup/athena_setup.yaml \
  --parameters \
      ParameterKey=ProformaBucketName,ParameterValue="$PROFORMA_BUCKET_NAME" \
      ParameterKey=RISPBucketName,ParameterValue="$RISP_BUCKET_NAME" \
      ParameterKey=ProformaReportName,ParameterValue="$PROFORMA_REPORT_NAME" \
      ParameterKey=RISPReportName,ParameterValue="$RISP_REPORT_NAME" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --tags Key=TestModule,Value=Module5 Key=TestRun,Value=$TIMESTAMP

echo "栈创建请求已提交: $MODULE5_STACK_NAME" | tee -a $LOG_FILE
```

### 步骤5: 监控部署进度
```bash
# 监控栈创建状态
echo "监控栈部署状态（预计15分钟）..." | tee -a $LOG_FILE
START_TIME=$(date +%s)

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name $MODULE5_STACK_NAME \
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
        --stack-name $MODULE5_STACK_NAME \
        --region $REGION \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
        --output table | tee -a $LOG_FILE
      exit 1
      ;;
    "CREATE_IN_PROGRESS")
      if [ $ELAPSED_MIN -gt 25 ]; then
        echo "⚠️  部署时间超过25分钟，可能有问题" | tee -a $LOG_FILE
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
export PROFORMA_DATABASE_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE5_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ProformaDatabaseName`].OutputValue' \
  --output text)

export RISP_DATABASE_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE5_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPDatabaseName`].OutputValue' \
  --output text)

export PROFORMA_CRAWLER_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE5_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ProformaCrawlerName`].OutputValue' \
  --output text)

export RISP_CRAWLER_NAME=$(aws cloudformation describe-stacks \
  --stack-name $MODULE5_STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPCrawlerName`].OutputValue' \
  --output text)

echo "Pro forma数据库名称: $PROFORMA_DATABASE_NAME" | tee -a $LOG_FILE
echo "RISP数据库名称: $RISP_DATABASE_NAME" | tee -a $LOG_FILE
echo "Pro forma Crawler名称: $PROFORMA_CRAWLER_NAME" | tee -a $LOG_FILE
echo "RISP Crawler名称: $RISP_CRAWLER_NAME" | tee -a $LOG_FILE
```

## 部署验证检查

### 1. 验证Glue数据库创建
```bash
echo "=== 验证Glue数据库创建 ===" | tee -a $LOG_FILE

# 检查Pro forma数据库是否存在
echo "--- Pro forma数据库验证 ---" | tee -a $LOG_FILE
PROFORMA_DB_EXISTS=$(aws glue get-database --name $PROFORMA_DATABASE_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$PROFORMA_DB_EXISTS" != "ERROR" ]; then
  echo "✅ Pro forma数据库创建成功: $PROFORMA_DATABASE_NAME" | tee -a $LOG_FILE
  aws glue get-database --name $PROFORMA_DATABASE_NAME --region $REGION \
    --query 'Database.{Name:Name,Description:Description}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ Pro forma数据库不存在: $PROFORMA_DATABASE_NAME" | tee -a $LOG_FILE
fi

# 检查RISP数据库是否存在
echo "--- RISP数据库验证 ---" | tee -a $LOG_FILE
RISP_DB_EXISTS=$(aws glue get-database --name $RISP_DATABASE_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$RISP_DB_EXISTS" != "ERROR" ]; then
  echo "✅ RISP数据库创建成功: $RISP_DATABASE_NAME" | tee -a $LOG_FILE
  aws glue get-database --name $RISP_DATABASE_NAME --region $REGION \
    --query 'Database.{Name:Name,Description:Description}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ RISP数据库不存在: $RISP_DATABASE_NAME" | tee -a $LOG_FILE
fi

# 验证数据分离正确性（重要！）
echo "--- 数据分离验证 ---" | tee -a $LOG_FILE
echo "⚠️  重要：验证数据是否正确分离到各自数据库" | tee -a $LOG_FILE

# 检查Pro forma数据库中的表
echo "Pro forma数据库表（应仅包含Pro forma相关表）:" | tee -a $LOG_FILE
PROFORMA_TABLES=$(aws glue get-tables --database-name $PROFORMA_DATABASE_NAME --region $REGION \
  --query 'TableList[].{Name:Name,Location:StorageDescriptor.Location}' \
  --output table 2>/dev/null | tee -a $LOG_FILE)

# 检查是否有错误的RISP表在Pro forma数据库中
RISP_IN_PROFORMA=$(aws glue get-tables --database-name $PROFORMA_DATABASE_NAME --region $REGION \
  --query 'TableList[?contains(Name, `risp`)].Name' --output text 2>/dev/null)

if [ -n "$RISP_IN_PROFORMA" ] && [ "$RISP_IN_PROFORMA" != "None" ]; then
  echo "❌ 错误：Pro forma数据库包含RISP表: $RISP_IN_PROFORMA" | tee -a $LOG_FILE
  echo "🔧 需要手动清理：aws glue delete-table --database-name $PROFORMA_DATABASE_NAME --name [RISP表名]" | tee -a $LOG_FILE
else
  echo "✅ Pro forma数据库数据分离正确" | tee -a $LOG_FILE
fi

# 检查RISP数据库中的表
echo "--- RISP数据库中的表 ---" | tee -a $LOG_FILE
aws glue get-tables --database-name $RISP_DATABASE_NAME --region $REGION \
  --query 'TableList[].{Name:Name,Location:StorageDescriptor.Location}' \
  --output table | tee -a $LOG_FILE

# 验证RISP表位置正确性
PROFORMA_IN_RISP=$(aws glue get-tables --database-name $RISP_DATABASE_NAME --region $REGION \
  --query 'TableList[?contains(Location, `bip-cur-`) && !contains(Location, `risp`)].Name' --output text 2>/dev/null)

if [ -n "$PROFORMA_IN_RISP" ] && [ "$PROFORMA_IN_RISP" != "None" ]; then
  echo "❌ 错误：RISP数据库包含Pro forma数据路径的表: $PROFORMA_IN_RISP" | tee -a $LOG_FILE
else
  echo "✅ RISP数据库数据分离正确" | tee -a $LOG_FILE
fi
```

### 2. 验证Glue Crawler创建
```bash
echo "=== 验证Glue Crawler创建 ===" | tee -a $LOG_FILE

# 检查Pro forma Crawler
echo "--- Pro forma Crawler状态 ---" | tee -a $LOG_FILE
PROFORMA_CRAWLER_STATUS=$(aws glue get-crawler --name $PROFORMA_CRAWLER_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$PROFORMA_CRAWLER_STATUS" != "ERROR" ]; then
  echo "✅ Pro forma Crawler创建成功: $PROFORMA_CRAWLER_NAME" | tee -a $LOG_FILE
  aws glue get-crawler --name $PROFORMA_CRAWLER_NAME --region $REGION \
    --query 'Crawler.{Name:Name,State:State,DatabaseName:DatabaseName,Targets:Targets}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ Pro forma Crawler不存在: $PROFORMA_CRAWLER_NAME" | tee -a $LOG_FILE
fi

# 检查RISP Crawler
echo "--- RISP Crawler状态 ---" | tee -a $LOG_FILE
RISP_CRAWLER_STATUS=$(aws glue get-crawler --name $RISP_CRAWLER_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$RISP_CRAWLER_STATUS" != "ERROR" ]; then
  echo "✅ RISP Crawler创建成功: $RISP_CRAWLER_NAME" | tee -a $LOG_FILE
  aws glue get-crawler --name $RISP_CRAWLER_NAME --region $REGION \
    --query 'Crawler.{Name:Name,State:State,DatabaseName:DatabaseName,Targets:Targets}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ RISP Crawler不存在: $RISP_CRAWLER_NAME" | tee -a $LOG_FILE
fi
```

### 3. 验证Lambda函数创建
```bash
echo "=== 验证Lambda函数创建 ===" | tee -a $LOG_FILE

# 检查Athena环境创建Lambda函数
LAMBDA_FUNCTION_NAME="CreateAthenaEnvironment"
LAMBDA_EXISTS=$(aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$LAMBDA_EXISTS" != "ERROR" ]; then
  echo "✅ Athena环境Lambda函数创建成功: $LAMBDA_FUNCTION_NAME" | tee -a $LOG_FILE
  aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $REGION \
    --query 'Configuration.{Name:FunctionName,Runtime:Runtime,Timeout:Timeout,MemorySize:MemorySize}' \
    --output table | tee -a $LOG_FILE
else
  echo "❌ Lambda函数不存在: $LAMBDA_FUNCTION_NAME" | tee -a $LOG_FILE
fi

# 检查S3事件处理Lambda函数
S3_LAMBDA_FUNCTION_NAME="ProcessCURDataUpdates"
S3_LAMBDA_EXISTS=$(aws lambda get-function --function-name $S3_LAMBDA_FUNCTION_NAME --region $REGION 2>/dev/null || echo "ERROR")

if [ "$S3_LAMBDA_EXISTS" != "ERROR" ]; then
  echo "✅ S3事件处理Lambda函数创建成功: $S3_LAMBDA_FUNCTION_NAME" | tee -a $LOG_FILE
else
  echo "ℹ️  S3事件处理Lambda函数可能使用不同名称或不存在" | tee -a $LOG_FILE
fi
```

### 4. 验证S3事件通知配置
```bash
echo "=== 验证S3事件通知配置 ===" | tee -a $LOG_FILE

# 检查Pro forma存储桶的事件通知
echo "--- Pro forma存储桶事件通知 ---" | tee -a $LOG_FILE
aws s3api get-bucket-notification-configuration --bucket $PROFORMA_BUCKET_NAME \
  --region $REGION 2>/dev/null | jq . | tee -a $LOG_FILE || echo "无事件通知配置"

# 检查RISP存储桶的事件通知
echo "--- RISP存储桶事件通知 ---" | tee -a $LOG_FILE
aws s3api get-bucket-notification-configuration --bucket $RISP_BUCKET_NAME \
  --region $REGION 2>/dev/null | jq . | tee -a $LOG_FILE || echo "无事件通知配置"
```

### 5. 验证Crawler运行状态
```bash
echo "=== 验证Crawler运行状态 ===" | tee -a $LOG_FILE

# 检查Crawler运行历史
echo "--- Pro forma Crawler运行历史 ---" | tee -a $LOG_FILE
aws glue get-crawler-metrics --crawler-name-list $PROFORMA_CRAWLER_NAME --region $REGION \
  --query 'CrawlerMetricsList[0]' --output table | tee -a $LOG_FILE

echo "--- RISP Crawler运行历史 ---" | tee -a $LOG_FILE
aws glue get-crawler-metrics --crawler-name-list $RISP_CRAWLER_NAME --region $REGION \
  --query 'CrawlerMetricsList[0]' --output table | tee -a $LOG_FILE

# 如果CUR数据存在，可以手动运行Crawler进行测试
PROFORMA_OBJECTS=$(aws s3 ls s3://$PROFORMA_BUCKET_NAME/ --recursive | wc -l)
RISP_OBJECTS=$(aws s3 ls s3://$RISP_BUCKET_NAME/ --recursive | wc -l)

echo "Pro forma存储桶对象数: $PROFORMA_OBJECTS" | tee -a $LOG_FILE
echo "RISP存储桶对象数: $RISP_OBJECTS" | tee -a $LOG_FILE

if [ $PROFORMA_OBJECTS -gt 0 ] || [ $RISP_OBJECTS -gt 0 ]; then
  echo "ℹ️  发现CUR数据，可以测试运行Crawler" | tee -a $LOG_FILE
  
  # 可选：测试运行Crawler
  read -p "是否要测试运行Crawler？(y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "启动Crawler测试运行..." | tee -a $LOG_FILE
    aws glue start-crawler --name $PROFORMA_CRAWLER_NAME --region $REGION
    aws glue start-crawler --name $RISP_CRAWLER_NAME --region $REGION
    echo "Crawler已启动，可通过AWS控制台查看进度" | tee -a $LOG_FILE
  fi
else
  echo "ℹ️  CUR数据尚未生成，Crawler将在数据可用时自动运行" | tee -a $LOG_FILE
fi
```

### 6. 验证Lambda执行日志
```bash
echo "=== 验证Lambda执行日志 ===" | tee -a $LOG_FILE

# 检查主要Lambda函数日志
LOG_GROUP="/aws/lambda/CreateAthenaEnvironment"
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

完成以下所有检查项表示模组5测试成功：

### Glue数据库检查
- [ ] Pro forma数据库创建成功并可访问 (athenacurcfn_{account_id})
- [ ] RISP数据库创建成功并可访问 (athenacurcfn_risp_{account_id})
- [ ] 两个数据库名称正确（包含账户ID）
- [ ] 两个数据库可用于Athena查询
- [ ] **数据分离正确性验证** ⚠️ **关键检查**
  - [ ] Pro forma数据库不包含RISP表
  - [ ] RISP数据库不包含Pro forma表
  - [ ] 表的S3路径与数据库类型匹配

### Glue Crawler检查
- [ ] Pro forma Crawler创建成功并配置正确
- [ ] RISP Crawler创建成功并配置正确
- [ ] Pro forma Crawler指向正确的S3存储桶和数据库
- [ ] RISP Crawler指向正确的S3存储桶和数据库
- [ ] 两个Crawler状态为READY或RUNNING

### Lambda函数检查
- [ ] 环境创建Lambda函数执行成功
- [ ] S3事件处理Lambda函数创建（如适用）
- [ ] Lambda函数权限配置正确

### S3集成检查
- [ ] S3事件通知配置正确（如适用）
- [ ] CUR存储桶与Crawler正确关联

### 系统功能检查
- [ ] CloudFormation栈状态为CREATE_COMPLETE
- [ ] 无资源创建失败
- [ ] 所有输出值正确生成

## 故障排除

### 常见问题1: 数据分离错误
**症状**: Pro forma数据库包含RISP表，或RISP数据库包含Pro forma表
**原因**: Crawler历史配置导致数据写入错误数据库
**解决方案**:
```bash
# 检查数据分离状态
echo "检查Pro forma数据库中是否有RISP表:"
aws glue get-tables --database-name $PROFORMA_DATABASE_NAME --region $REGION \
  --query 'TableList[?contains(Name, `risp`)].{Name:Name,Location:StorageDescriptor.Location}' \
  --output table

# 如发现错误表，手动删除
aws glue delete-table --database-name $PROFORMA_DATABASE_NAME --name [错误的RISP表名] --region $REGION

# 重新启动对应Crawler
aws glue start-crawler --name $PROFORMA_CRAWLER_NAME --region $REGION
aws glue start-crawler --name $RISP_CRAWLER_NAME --region $REGION
```

### 常见问题2: Glue数据库创建失败
**症状**: 数据库创建失败或无法访问
**解决方案**:
```bash
# 检查Glue权限
aws sts get-caller-identity
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names glue:CreateDatabase \
  --resource-arns "*"

# 检查数据库是否已存在
aws glue get-databases --region $REGION --query 'DatabaseList[].Name'
```

### 常见问题2: Crawler配置错误
**症状**: Crawler创建失败或配置不正确
**解决方案**:
```bash
# 检查S3存储桶权限
aws s3 ls s3://$PROFORMA_BUCKET_NAME/
aws s3 ls s3://$RISP_BUCKET_NAME/

# 检查Crawler IAM角色
aws iam get-role --role-name AWSGlueServiceRole-CURCrawler 2>/dev/null
```

### 常见问题3: Lambda执行超时
**症状**: Lambda函数执行超过900秒
**解决方案**:
```bash
# 检查Lambda函数配置
aws lambda get-function-configuration --function-name CreateAthenaEnvironment

# 查看详细错误日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/CreateAthenaEnvironment \
  --filter-pattern "ERROR"
```

### 常见问题4: 参数传递错误
**症状**: 存储桶或报告名称参数不正确
**解决方案**:
```bash
# 验证所有参数
echo "ProformaBucketName: $PROFORMA_BUCKET_NAME"
echo "RISPBucketName: $RISP_BUCKET_NAME"
echo "ProformaReportName: $PROFORMA_REPORT_NAME"
echo "RISPReportName: $RISP_REPORT_NAME"

# 重新检查模组3和4的输出
source /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
```

## 清理步骤

如果需要清理模组5资源：

```bash
echo "开始清理模组5资源..." | tee -a $LOG_FILE

# 删除Glue表（如果存在）
for DATABASE in "$PROFORMA_DATABASE_NAME" "$RISP_DATABASE_NAME"; do
  if [ -n "$DATABASE" ]; then
    echo "删除数据库中的表: $DATABASE" | tee -a $LOG_FILE
    TABLES=$(aws glue get-tables --database-name $DATABASE --region $REGION \
      --query 'TableList[].Name' --output text 2>/dev/null)
    
    for TABLE in $TABLES; do
      echo "删除表: $TABLE" | tee -a $LOG_FILE
      aws glue delete-table --database-name $DATABASE --name $TABLE --region $REGION
    done
  fi
done

# 删除CloudFormation栈
aws cloudformation delete-stack \
  --stack-name $MODULE5_STACK_NAME \
  --region $REGION

echo "等待栈删除完成..." | tee -a $LOG_FILE

# 监控删除进度
aws cloudformation wait stack-delete-complete \
  --stack-name $MODULE5_STACK_NAME \
  --region $REGION

echo "✅ 模组5资源清理完成" | tee -a $LOG_FILE
```

## 下一步

模组5测试成功后：
1. 保存Athena数据库名称和Crawler名称变量
2. 可以继续执行模组6和模组7测试
3. 等待CUR数据生成后测试Athena查询

```bash
# 保存关键变量供参考
echo "export PROFORMA_DATABASE_NAME='$PROFORMA_DATABASE_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export RISP_DATABASE_NAME='$RISP_DATABASE_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export PROFORMA_CRAWLER_NAME='$PROFORMA_CRAWLER_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export RISP_CRAWLER_NAME='$RISP_CRAWLER_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh
echo "export MODULE5_STACK_NAME='$MODULE5_STACK_NAME'" >> /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

echo "✅ 模组5测试完成，变量已保存" | tee -a $LOG_FILE
echo "🎯 下一步: 可以并行执行模组6 (账户自动移动) 和模组7 (CloudFront监控) 测试" | tee -a $LOG_FILE
echo "ℹ️  当CUR数据生成后，可以使用Athena查询分析数据" | tee -a $LOG_FILE

# Athena查询示例
cat << 'EOF' | tee -a $LOG_FILE

=== Athena查询示例（数据生成后使用） ===

-- 查看Pro forma CUR数据
SELECT line_item_product_code, SUM(line_item_blended_cost) as total_cost 
FROM "${PROFORMA_DATABASE_NAME}"."${PROFORMA_REPORT_NAME}" 
WHERE year='2024' AND month='01' 
GROUP BY line_item_product_code 
ORDER BY total_cost DESC LIMIT 10;

-- 查看RISP CUR数据
SELECT line_item_product_code, SUM(line_item_unblended_cost) as total_cost 
FROM "${RISP_DATABASE_NAME}"."${RISP_REPORT_NAME}" 
WHERE year='2024' AND month='01' 
GROUP BY line_item_product_code 
ORDER BY total_cost DESC LIMIT 10;

EOF
```