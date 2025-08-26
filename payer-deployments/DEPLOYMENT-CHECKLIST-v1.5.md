# Payer部署检查清单 v1.5

## 📋 部署前检查

### 环境准备
- [ ] AWS CLI配置完成，具备完整管理员权限
- [ ] 确认在us-east-1区域进行部署
- [ ] 检查Organizations服务已启用
- [ ] 验证账户邮箱格式正确 (支持+bills别名)

### 版本确认
- [ ] 使用v1.5版本 (当前推荐版本)
- [ ] 确认current符号链接指向v1.5
- [ ] 检查version-registry.json状态为stable

## 🚀 逐模块部署检查

### Module 1: OU和SCP设置
**预检查**:
- [ ] 获取Root ID: `aws organizations list-roots --query 'Roots[0].Id' --output text`

**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 01-ou-scp v1.5 <payer-name>-ou-scp --root-id $ROOT_ID
```

**验证**:
- [ ] 栈状态: `CREATE_COMPLETE`
- [ ] 创建3个OU: Free, Block, Normal
- [ ] 7个SCP策略已附加

---

### Module 2: BillingConductor设置
**预检查**:
- [ ] 检查是否已存在BillingGroup: `aws billingconductor list-billing-groups`

**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 02-billing-conductor v1.5 <payer-name>-billing-conductor
```

**验证**:
- [ ] Bills账户创建成功或使用现有账户
- [ ] BillingGroup创建成功，名称为"Bills"
- [ ] 记录BillingGroup ARN

---

### Module 3: Pro forma CUR Export
**预检查**:
- [ ] 获取BillingGroup ARN

**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 03-cur-proforma v1.5 <payer-name>-cur-proforma --billing-group-arn $BILLING_GROUP_ARN
```

**验证**:
- [ ] 栈状态: `CREATE_COMPLETE` 
- [ ] S3 Bucket创建: `bip-cur-<ACCOUNT_ID>`
- [ ] CUR报告配置正确，名称为<ACCOUNT_ID>

---

### Module 4: RISP CUR Export
**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 04-cur-risp v1.5 <payer-name>-cur-risp
```

**验证**:
- [ ] 栈状态: `CREATE_COMPLETE`
- [ ] S3 Bucket创建: `bip-risp-cur-<ACCOUNT_ID>`
- [ ] CUR报告配置正确，名称为risp-<ACCOUNT_ID>

---

### Module 5: Athena Setup ⚠️ 重点关注
**预检查**:
```bash
# 确认参数正确性
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROFORMA_BUCKET=bip-cur-$ACCOUNT_ID  
RISP_BUCKET=bip-risp-cur-$ACCOUNT_ID

echo "✅ ProformaReportName将使用: $ACCOUNT_ID"
echo "❌ 不要使用: proforma-$ACCOUNT_ID"
```

**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 05-athena-setup v1.5 <payer-name>-athena-setup \
  --parameters \
  ProformaBucketName=$PROFORMA_BUCKET \
  RISPBucketName=$RISP_BUCKET \
  ProformaReportName=$ACCOUNT_ID \
  RISPReportName=risp-$ACCOUNT_ID
```

**关键验证**:
- [ ] 栈状态: `CREATE_COMPLETE`
- [ ] 创建2个Glue数据库: `athenacurcfn_<ACCOUNT_ID>`, `athenacurcfn_risp_<ACCOUNT_ID>`
- [ ] 创建2个Crawler: `AWSCURCrawler-<ACCOUNT_ID>`, `AWSCURCrawler-RISP-<ACCOUNT_ID>`
- [ ] ⚠️ **Pro forma Crawler路径**: `s3://<bucket>/daily/<ACCOUNT_ID>/` (不含proforma前缀!)
- [ ] RISP Crawler路径: `s3://<bucket>/daily/risp-<ACCOUNT_ID>/`
- [ ] 两个Crawler都配置了调度: `cron(0 2 * * ? *)`

**数据验证**:
```bash
# 手动运行Crawler
aws glue start-crawler --name AWSCURCrawler-$ACCOUNT_ID
aws glue start-crawler --name AWSCURCrawler-RISP-$ACCOUNT_ID

# 等待60秒后检查表创建
aws glue get-tables --database-name athenacurcfn_$ACCOUNT_ID --query 'TableList[*].Name'
```
- [ ] Pro forma数据库包含表: `<ACCOUNT_ID>`, `cost_and_usage_data_status`
- [ ] RISP数据库包含表: `risp_<ACCOUNT_ID>`, `cost_and_usage_data_status`

---

### Module 6: Account Auto Management
**预检查**:
- [ ] 获取Normal OU ID

**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 06-account-auto-management v1.5 <payer-name>-account-auto-management --normal-ou-id $NORMAL_OU_ID
```

**验证**:
- [ ] 栈状态: `CREATE_COMPLETE`
- [ ] Lambda函数创建成功
- [ ] EventBridge规则配置正确

---

### Module 7: CloudFront Monitoring
**预检查**:
- [ ] 获取Payer名称

**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 07-cloudfront-monitoring v1.5 <payer-name>-cloudfront-monitoring --payer-name "<PAYER_NAME>"
```

**验证**:
- [ ] 栈状态: `CREATE_COMPLETE`
- [ ] OAM Sink和Link创建成功
- [ ] CloudWatch告警配置(5GB阈值)

---

### Module 8: IAM Users
**部署命令**:
```bash
./deployment-scripts/version-management.sh deploy 08-iam-users v1.5 <payer-name>-iam-users
```

**验证**:
- [ ] 栈状态: `CREATE_COMPLETE`
- [ ] 创建2个IAM用户: `cost_explorer`, `ReadOnly_system`
- [ ] Console登录配置完成

## 🔍 最终验证

### 全栈状态检查
```bash
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `<payer-name>`)].{Name:StackName,Status:StackStatus}' \
  --output table
```
- [ ] 8个栈全部显示 `CREATE_COMPLETE`

### Athena数据测试 (关键验证)
```bash
# 在Athena控制台执行测试查询
SELECT * FROM athenacurcfn_<ACCOUNT_ID>.<ACCOUNT_ID> 
WHERE year='2025' AND month='8' LIMIT 5;

SELECT * FROM athenacurcfn_risp_<ACCOUNT_ID>.risp_<ACCOUNT_ID>
WHERE year='2025' AND month='8' LIMIT 5;
```
- [ ] Pro forma查询返回数据
- [ ] RISP查询返回数据

### Organizations结构验证
```bash
aws organizations list-organizational-units-for-parent --parent-id $ROOT_ID \
  --query 'OrganizationalUnits[*].Name' --output text
```
- [ ] 确认包含: Free, Block, Normal

### 部署总结
- [ ] 部署完成时间: ___________
- [ ] 所有模块状态: 8/8 ✅
- [ ] Athena数据验证: ✅
- [ ] 问题记录: ___________

## 🚨 常见问题解决

### Module 5 Athena无数据
**症状**: Crawler运行成功但Athena查询无数据
**解决**: 
1. 检查`ProformaReportName`参数是否为纯账户ID
2. 验证Crawler路径配置是否正确
3. v1.5版本已自动修复此问题

### IAM角色传播错误
**症状**: `Service is unable to assume provided role`
**解决**: v1.5版本已添加30秒等待时间自动解决

### BillingGroup已存在
**症状**: BillingGroup创建失败，已存在同名资源
**解决**: 跳过Module 2，使用现有BillingGroup ARN部署Module 3

## 📞 支持

如遇到未列出的问题，请参考:
- `MODULE-5-DEPLOYMENT-GUIDE.md` - Module 5专项指南
- `aws-payer-automation/README.md` - 详细故障排除
- `version-registry.json` - 版本问题记录