# Elite-new17 快速参考

这个文件包含部署过程中所有关键命令和输出参数的快速参考。

## 环境设置

```bash
# 设置 AWS Profile
export AWS_PROFILE=Elite-new17

# 获取基本信息
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)

# 进入工作目录
cd /Users/di.miao/Work/BIP/payer-setup/aws-payer-automation
```

**记录区域**:
- ACCOUNT_ID: _______________
- ROOT_ID: _______________
- REGION: us-east-1

---

## Module 1: OU和SCP

### 部署命令
```bash
./scripts/deploy-single.sh 1 --root-id $ROOT_ID
```

### 获取输出
```bash
# Normal OU ID
NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name payer-*-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text)

echo "NORMAL_OU_ID: $NORMAL_OU_ID"
```

**记录区域**:
- Stack Name: _______________
- NormalOUId: _______________
- FreeOUId: _______________
- BlockOUId: _______________

---

## Module 2: BillingConductor

### 预检查
```bash
# 检查是否已存在
aws billingconductor list-billing-groups \
  --query 'BillingGroups[?Name==`Bills`]'
```

### 部署命令（如果不存在）
```bash
./scripts/deploy-single.sh 2
```

### 获取输出
```bash
# 获取 BillingGroup ARN（新部署或已存在）
BILLING_GROUP_ARN=$(aws billingconductor list-billing-groups \
  --query 'BillingGroups[?Name==`Bills`].Arn' \
  --output text)

echo "BILLING_GROUP_ARN: $BILLING_GROUP_ARN"
```

**记录区域**:
- Stack Name: _______________ (或 SKIPPED)
- BillingGroupArn: _______________

---

## Module 3: Pro forma CUR

### 部署命令
```bash
./scripts/deploy-single.sh 3 --billing-group-arn $BILLING_GROUP_ARN
```

### 获取输出
```bash
# Pro forma Bucket
PROFORMA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-proforma-* \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

echo "PROFORMA_BUCKET: $PROFORMA_BUCKET"
```

**记录区域**:
- Stack Name: _______________
- BucketName: _______________ (应该是 bip-cur-ACCOUNT_ID)
- ReportName: _______________ (应该是 ACCOUNT_ID)

---

## Module 4: RISP CUR

### 部署命令
```bash
./scripts/deploy-single.sh 4
```

### 获取输出
```bash
# RISP Bucket
RISP_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-risp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPBucketName`].OutputValue' \
  --output text)

echo "RISP_BUCKET: $RISP_BUCKET"
```

**记录区域**:
- Stack Name: _______________
- RISPBucketName: _______________ (应该是 bip-risp-cur-ACCOUNT_ID)
- RISPReportName: _______________ (应该是 risp-ACCOUNT_ID)

---

## Module 5: Athena Setup ⚠️ CRITICAL

### 参数准备
```bash
# 验证所有参数
echo "ACCOUNT_ID: $ACCOUNT_ID"
echo "PROFORMA_BUCKET: $PROFORMA_BUCKET"
echo "RISP_BUCKET: $RISP_BUCKET"

# ⚠️ 关键：ProformaReportName 必须只是账户ID，不能有 proforma- 前缀！
echo "ProformaReportName will be: $ACCOUNT_ID"
```

### 部署命令
```bash
STACK_NAME=payer-Elite-new17-athena-setup-$(date +%s)

./deployment-scripts/version-management.sh deploy 05-athena-setup v1.5 \
  $STACK_NAME \
  --parameters \
  ProformaBucketName=$PROFORMA_BUCKET \
  RISPBucketName=$RISP_BUCKET \
  ProformaReportName=$ACCOUNT_ID \
  RISPReportName=risp-$ACCOUNT_ID
```

### 关键验证（必须执行）
```bash
# 1. 检查 Crawler 创建
aws glue list-crawlers --query 'CrawlerNames[?contains(@, `'$ACCOUNT_ID'`)]'

# 2. ⚠️ 验证 Crawler 路径（最关键）
aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.Targets.S3Targets[0].Path'

# ✅ 正确路径: s3://bip-cur-ACCOUNT_ID/daily/ACCOUNT_ID/
# ❌ 错误路径: s3://bip-cur-ACCOUNT_ID/daily/proforma-ACCOUNT_ID/

# 3. 手动触发 Crawler
aws glue start-crawler --name AWSCURCrawler-$ACCOUNT_ID
sleep 60
aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID --query 'Crawler.State'

# 4. 检查数据库和表
aws glue get-tables --database-name athenacurcfn_$ACCOUNT_ID
```

**记录区域**:
- Stack Name: _______________
- DatabaseName: _______________ (应该是 athenacurcfn_ACCOUNT_ID)
- ProformaCrawler: _______________
- RISPCrawler: _______________
- ✅ Crawler Path Verified: [ ] YES / [ ] NO
- Crawler Path: _______________

---

## Module 6: Account Auto Management

### 部署命令
```bash
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID
```

**记录区域**:
- Stack Name: _______________
- Lambda Function: _______________
- EventBridge Rule: _______________

---

## Module 7: CloudFront Monitoring

### 部署命令
```bash
./scripts/deploy-single.sh 7 \
  --payer-name "Elite-new17" \
  --threshold-mb 5120
```

**记录区域**:
- Stack Name: _______________
- OAM Sink: _______________
- CloudWatch Alarm: _______________
- Threshold: 5120 MB (5GB)
- Telegram Group: -862835857

---

## Module 8: IAM Users

### 部署命令
```bash
./deployment-scripts/version-management.sh deploy 08-iam-users v1.5 \
  payer-Elite-new17-iam-users-$(date +%s)
```

**记录区域**:
- Stack Name: _______________
- Users Created:
  - [ ] cost_explorer
  - [ ] ReadOnly_system
- Default Password: Password1! (首次登录必须修改)

---

## 快速验证命令

### 检查所有栈状态
```bash
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `payer`)].{Name:StackName,Status:StackStatus}' \
  --output table
```

### 验证 OU 结构
```bash
aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_ID \
  --query 'OrganizationalUnits[*].{Name:Name,Id:Id}' \
  --output table
```

### 验证 S3 Buckets
```bash
aws s3 ls | grep bip
```

### 验证 Glue Crawlers
```bash
aws glue list-crawlers
```

### 验证 Lambda 函数
```bash
aws lambda list-functions --query 'Functions[*].FunctionName'
```

### 验证 IAM 用户
```bash
aws iam list-users \
  --query 'Users[?contains(UserName, `cost_explorer`) || contains(UserName, `ReadOnly`)].UserName'
```

---

## 完整部署脚本

如果想一次性部署所有模块，可以使用：

```bash
cd /Users/di.miao/Work/BIP/payer-setup/payer-deployments/scripts
bash deploy-elite-new17.sh
```

这个脚本会：
- 自动设置环境变量
- 逐步部署所有8个模块
- 自动捕获和记录输出参数
- 在每个模块后进行验证
- 保存完整日志

---

## 完整验证脚本

部署完成后，运行验证脚本：

```bash
cd /Users/di.miao/Work/BIP/payer-setup/payer-deployments/scripts
bash verify-elite-new17.sh
```

这个脚本会验证：
- 所有栈的状态
- OU 组织结构
- S3 Buckets
- Glue Crawler 路径（关键）
- Lambda 函数
- IAM 用户
- Athena 数据查询能力

---

## 重要提醒

### ⚠️ 关键点
1. **Module 5 是最关键的模块**
   - 必须使用 v1.5 版本
   - ProformaReportName 参数只能是账户ID
   - 必须验证 Crawler 路径没有 proforma- 前缀

2. **环境变量**
   - 每次新终端都要重新设置 `export AWS_PROFILE=Elite-new17`
   - 建议在 `.bashrc` 或 `.zshrc` 中添加

3. **并行部署**
   - 使用环境变量方式可以同时部署多个 Payer
   - 每个 Payer 在独立终端会话中部署

4. **数据延迟**
   - CUR 数据需要 24 小时生成
   - 部署完成后立即查询 Athena 会返回空结果（这是正常的）

---

## 故障排查

### Module 5 IAM 角色错误
- 错误信息: "Service is unable to assume role"
- 解决方案: v1.5 已自动包含 30 秒等待，如仍失败等待 2 分钟重试

### Athena 查询无数据
- 最常见原因: Crawler 路径包含 proforma- 前缀
- 解决方案: 验证并修复 Crawler 路径配置

### BillingGroup 已存在
- 这是正常情况，跳过 Module 2 部署
- 直接获取现有 ARN 用于 Module 3

---

**最后更新**: 2025-11-20
**状态**: 准备就绪
