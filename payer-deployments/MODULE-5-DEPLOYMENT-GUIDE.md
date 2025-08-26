# Module 5 Athena Setup 部署指南 v1.5

## ⚠️ 重要提醒

**使用v1.5修复版本**:
- 模板: `athena_setup_fixed.yaml` 
- 版本: `v1.5` (包含IAM角色传播和Crawler路径双重修复)

## 🎯 关键参数配置

### ProformaReportName 参数
```bash
# ❌ 错误 - 不要使用proforma前缀
ProformaReportName=proforma-534877455433

# ✅ 正确 - 直接使用主账户ID  
ProformaReportName=534877455433
```

### 完整参数示例
```bash
# 部署Module 5的正确参数
ProformaBucketName=bip-cur-534877455433           # 来自Module 3输出
RISPBucketName=bip-risp-cur-534877455433          # 来自Module 4输出
ProformaReportName=534877455433                   # 主账户ID (重要!)
RISPReportName=risp-534877455433                  # RISP报告名称
```

## 📋 部署步骤

### 1. 获取前置参数
```bash
# 获取主账户ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 获取Module 3 Pro forma Bucket
PROFORMA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name *cur-proforma* \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

# 获取Module 4 RISP Bucket  
RISP_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name *cur-risp* \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPBucketName`].OutputValue' \
  --output text)

echo "Account ID: $ACCOUNT_ID"
echo "Pro forma Bucket: $PROFORMA_BUCKET"
echo "RISP Bucket: $RISP_BUCKET"
```

### 2. 使用版本管理脚本部署
```bash
cd ../aws-payer-automation

# 使用v1.5版本部署
./deployment-scripts/version-management.sh deploy 05-athena-setup v1.5 <payer-name>-athena-setup \
  --parameters \
  ProformaBucketName=$PROFORMA_BUCKET \
  RISPBucketName=$RISP_BUCKET \
  ProformaReportName=$ACCOUNT_ID \
  RISPReportName=risp-$ACCOUNT_ID
```

### 3. 手动CloudFormation部署
```bash  
aws cloudformation create-stack \
  --stack-name <payer-name>-athena-setup \
  --template-body file://templates/versions/v1.5/05-athena-setup/athena_setup_fixed.yaml \
  --parameters \
    ParameterKey=ProformaBucketName,ParameterValue=$PROFORMA_BUCKET \
    ParameterKey=RISPBucketName,ParameterValue=$RISP_BUCKET \
    ParameterKey=ProformaReportName,ParameterValue=$ACCOUNT_ID \
    ParameterKey=RISPReportName,ParameterValue=risp-$ACCOUNT_ID \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
```

## 🔍 部署验证

### 1. 检查栈状态
```bash
aws cloudformation describe-stacks --stack-name <payer-name>-athena-setup \
  --query 'Stacks[0].StackStatus' --output text
```

### 2. 验证Glue资源
```bash
# 检查数据库
aws glue get-databases --query 'DatabaseList[?contains(Name, `'$ACCOUNT_ID'`)].Name' --output text

# 检查Crawler
aws glue list-crawlers --query 'CrawlerNames[?contains(@, `'$ACCOUNT_ID'`)]' --output text

# 检查Crawler路径配置
aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.Targets.S3Targets[0].Path' --output text
```

### 3. 验证S3路径匹配
```bash
# 检查Pro forma Crawler路径
CRAWLER_PATH=$(aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.Targets.S3Targets[0].Path' --output text)

# 检查实际CUR数据路径
aws s3 ls s3://$PROFORMA_BUCKET/daily/ | grep $ACCOUNT_ID

echo "Crawler路径: $CRAWLER_PATH"
echo "期望路径: s3://$PROFORMA_BUCKET/daily/$ACCOUNT_ID/"
```

### 4. 运行Crawler测试
```bash
# 手动启动Pro forma Crawler
aws glue start-crawler --name AWSCURCrawler-$ACCOUNT_ID

# 等待完成并检查状态
aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.{State:State,LastCrawl:LastCrawl.Status}' --output table
```

### 5. 验证Athena数据
```bash
# 列出创建的表
aws glue get-tables --database-name athenacurcfn_$ACCOUNT_ID \
  --query 'TableList[*].Name' --output text

# 如果有数据表，表示部署成功
```

## 🚨 故障排除

### 问题1: Athena无数据
**症状**: Glue数据库和Crawler创建成功，但Athena查询返回空结果

**检查**:
```bash
# 检查Crawler路径配置
aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.Targets.S3Targets[0].Path'

# 检查实际CUR数据位置
aws s3 ls s3://$PROFORMA_BUCKET/daily/ --recursive | head -5
```

**解决**:
- 确保`ProformaReportName`参数是账户ID (如534877455433)
- 不要使用"proforma-534877455433"格式
- v1.5版本已自动修复此问题

### 问题2: IAM角色无法assume
**症状**: `Service is unable to assume provided role`

**解决**:
- v1.5版本已添加30秒IAM角色传播等待
- 增加Lambda超时到600秒
- 如仍有问题，手动等待2分钟后重试

### 问题3: Crawler调度不工作
**检查**:
```bash
aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.Schedule'
```

**解决**:
- v1.5版本已自动配置每日凌晨2点调度
- 调度表达式: `cron(0 2 * * ? *)`

## 📊 成功标准

✅ **完全成功的标志**:
1. CloudFormation栈状态: `CREATE_COMPLETE`
2. 创建2个Glue数据库: `athenacurcfn_ACCOUNTID`, `athenacurcfn_risp_ACCOUNTID`
3. 创建2个Crawler: `AWSCURCrawler-ACCOUNTID`, `AWSCURCrawler-RISP-ACCOUNTID`
4. Pro forma Crawler路径: `s3://bucket/daily/ACCOUNTID/` (不含proforma前缀)
5. Crawler调度配置: `cron(0 2 * * ? *)`
6. 运行Crawler后Athena可查询到数据

## 🔄 版本管理

**推荐使用**: v1.5 (当前最新稳定版)
- 包含IAM角色传播修复
- 包含Crawler路径配置修复
- 包含自动调度配置
- Elite-new12生产环境验证通过

**避免使用**: v1.4及更早版本
- 存在Crawler路径配置问题
- 可能导致Athena无数据