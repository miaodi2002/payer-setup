# AWS Payer Automation - 故障排除指南

## 概述

本文档提供AWS Payer Automation项目7个模组的综合故障排除指南，帮助快速诊断和解决部署过程中遇到的问题。

## 目录
- [通用故障排除](#通用故障排除)
- [模组1故障排除](#模组1故障排除)
- [模组2故障排除](#模组2故障排除)
- [模组3故障排除](#模组3故障排除)
- [模组4故障排除](#模组4故障排除)
- [模组5故障排除](#模组5故障排除)
- [模组6故障排除](#模组6故障排除)
- [模组7故障排除](#模组7故障排除)
- [系统级问题](#系统级问题)
- [性能优化](#性能优化)

---

## 通用故障排除

### AWS CLI配置问题

#### 问题：AWS CLI未配置或凭证无效
**症状**：
```bash
Unable to locate credentials. You can configure credentials by running "aws configure".
```

**解决方案**：
```bash
# 检查当前配置
aws sts get-caller-identity

# 重新配置AWS CLI
aws configure

# 检查区域设置
aws configure get region

# 对于临时凭证，设置环境变量
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_SESSION_TOKEN=your_session_token  # 如果使用临时凭证
```

#### 问题：权限不足
**症状**：
```
An error occurred (AccessDenied) when calling the XXX operation
```

**解决方案**：
```bash
# 检查当前用户权限
aws sts get-caller-identity

# 检查特定服务权限
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names organizations:DescribeOrganization \
  --resource-arns "*"

# 参考README.md中的IAM策略要求
```

### CloudFormation通用问题

#### 问题：栈创建失败
**诊断步骤**：
```bash
# 查看栈事件
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]' \
  --output table

# 查看栈状态
aws cloudformation describe-stacks \
  --stack-name <stack-name> \
  --query 'Stacks[0].StackStatus'

# 查看详细错误信息
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}'
```

#### 问题：资源限制
**症状**：资源创建因为账户限制失败
**解决方案**：
```bash
# 检查服务限制
aws service-quotas get-service-quota \
  --service-code cloudformation \
  --quota-code L-0485CB21  # CloudFormation栈数量限制

# 请求增加限制
aws service-quotas request-service-quota-increase \
  --service-code cloudformation \
  --quota-code L-0485CB21 \
  --desired-value 200
```

---

## 模组1故障排除

### SCP策略问题

#### 问题：SCP功能未启用
**症状**：`SCPNotEnabled` 或 `FeatureSetNotSupported`
**解决方案**：
```bash
# 检查Organizations功能集
aws organizations describe-organization --query 'Organization.FeatureSet'

# 如果返回"CONSOLIDATED_BILLING"，需要启用全部功能
aws organizations enable-all-features
```

#### 问题：SCP附加失败
**症状**：Lambda函数报告SCP附加错误
**解决方案**：
```bash
# 检查Organizations权限
aws organizations list-policies --filter SERVICE_CONTROL_POLICY

# 手动测试SCP附加
aws organizations attach-policy \
  --policy-id <policy-id> \
  --target-id <ou-id>

# 检查Lambda函数日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/AttachSCPToOU \
  --filter-pattern "ERROR"
```

#### 问题：OU创建失败
**症状**：组织单元名称冲突
**解决方案**：
```bash
# 列出现有OU
aws organizations list-organizational-units-for-parent \
  --parent-id <root-id>

# 如果存在同名OU，先删除（必须为空）
aws organizations list-accounts-for-parent --parent-id <ou-id>
aws organizations delete-organizational-unit --organizational-unit-id <ou-id>
```

---

## 模组2故障排除

### 账户创建问题

#### 问题：账户创建超时
**症状**：CREATE_IN_PROGRESS状态超过45分钟
**解决方案**：
```bash
# 检查账户创建状态
aws organizations list-create-account-status \
  --states IN_PROGRESS

# 检查是否有失败的创建请求
aws organizations list-create-account-status \
  --states FAILED \
  --query 'CreateAccountStatuses[].FailureReason'

# 取消超时的创建请求（如果可能）
# 通常需要等待AWS完成或自动取消
```

#### 问题：邮箱地址冲突
**症状**：账户创建失败，邮箱已存在
**解决方案**：
```bash
# 检查现有账户邮箱
aws organizations list-accounts \
  --query "Accounts[?contains(Email, '+bills')]"

# Lambda会自动处理冲突，添加数字后缀
# 检查Lambda执行日志查看实际使用的邮箱
aws logs filter-log-events \
  --log-group-name /aws/lambda/CreateAccountAndBillingGroup \
  --filter-pattern "email"
```

### BillingConductor问题

#### 问题：BillingConductor服务不可用
**症状**：API调用失败或权限被拒绝
**解决方案**：
```bash
# 检查BillingConductor在当前区域是否可用
aws billingconductor list-billing-groups --region us-east-1
aws billingconductor list-billing-groups --region us-west-2

# BillingConductor仅在特定区域可用
# 确保在us-east-1区域部署
```

---

## 模组3故障排除

### CUR导出问题

#### 问题：CUR创建限制
**症状**：超过CUR报告数量限制
**解决方案**：
```bash
# 列出现有CUR报告
aws cur describe-report-definitions --region us-east-1

# 删除不需要的CUR报告
aws cur delete-report-definition \
  --report-name <report-name> \
  --region us-east-1

# AWS账户默认限制为5个CUR报告
```

#### 问题：S3存储桶策略错误
**症状**：AWS Billing无法写入S3存储桶
**解决方案**：
```bash
# 检查存储桶策略
aws s3api get-bucket-policy --bucket <bucket-name>

# 手动修复存储桶策略（允许AWS Billing访问）
cat > bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSBillingDeliveryRights",
      "Effect": "Allow",
      "Principal": {
        "Service": "billingreports.amazonaws.com"
      },
      "Action": [
        "s3:GetBucketAcl",
        "s3:GetBucketPolicy",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::<bucket-name>",
        "arn:aws:s3:::<bucket-name>/*"
      ]
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket <bucket-name> --policy file://bucket-policy.json
```

---

## 模组4故障排除

### RISP CUR问题

#### 问题：与Pro forma CUR冲突
**症状**：存储桶或报告名称冲突
**解决方案**：
```bash
# 检查两个CUR的配置
aws cur describe-report-definitions --region us-east-1 \
  --query 'ReportDefinitions[].{Name:ReportName,Bucket:S3Bucket}'

# 确保使用不同的存储桶和报告名称
# Pro forma: bip-cur-<account-id>
# RISP: bip-risp-cur-<account-id>
```

---

## 模组5故障排除

### Glue和Athena问题

#### 问题：Glue数据库创建失败
**症状**：权限被拒绝或服务不可用
**解决方案**：
```bash
# 检查Glue权限
aws glue get-databases --region us-east-1

# 检查IAM角色权限
aws iam get-role-policy \
  --role-name AWSGlueServiceRole \
  --policy-name GlueServiceRolePolicy

# 手动创建数据库（如果需要）
aws glue create-database \
  --database-input Name=athenacurcfn_<account-id>,Description="CUR Database"
```

#### 问题：Crawler无法访问S3数据
**症状**：Crawler运行失败，权限错误
**解决方案**：
```bash
# 检查Crawler IAM角色
aws glue get-crawler --name <crawler-name> \
  --query 'Crawler.Role'

# 检查S3存储桶权限
aws s3api get-bucket-policy --bucket <bucket-name>

# 手动运行Crawler测试
aws glue start-crawler --name <crawler-name>
```

#### 问题：CUR数据未生成
**症状**：S3存储桶为空，无法创建表
**解决方案**：
```bash
# 检查CUR报告配置
aws cur describe-report-definitions --region us-east-1

# CUR数据生成需要时间
# - 首次配置后24小时内生成
# - 每日更新
# - 检查账户是否有实际使用量
```

---

## 模组6故障排除

### EventBridge问题

#### 问题：EventBridge规则未触发
**症状**：新账户未自动移动到Normal OU
**解决方案**：
```bash
# 检查EventBridge规则状态
aws events list-rules --region us-east-1 \
  --query 'Rules[?contains(Name, `Account`)].{Name:Name,State:State}'

# 检查规则的事件模式
aws events describe-rule --name <rule-name>

# 手动测试规则
aws events put-events \
  --entries file://test-event.json
```

#### 问题：Lambda函数权限不足
**症状**：账户移动失败，权限被拒绝
**解决方案**：
```bash
# 检查Lambda执行角色
aws lambda get-function --function-name AccountAutoMover \
  --query 'Configuration.Role'

# 检查角色权限
aws iam get-role-policy \
  --role-name AccountAutoMoverRole \
  --policy-name OrganizationsAccess

# 手动测试账户移动
aws organizations move-account \
  --account-id <account-id> \
  --source-parent-id <source-ou> \
  --destination-parent-id <normal-ou>
```

### CloudTrail问题

#### 问题：CloudTrail创建失败
**症状**：S3权限错误或CloudTrail已存在
**解决方案**：
```bash
# 检查现有CloudTrail
aws cloudtrail describe-trails

# 检查CloudTrail S3存储桶权限
aws s3api get-bucket-policy --bucket <cloudtrail-bucket>

# 如果使用现有CloudTrail，确保记录Organizations事件
aws cloudtrail put-event-selectors \
  --trail-name <trail-name> \
  --event-selectors file://event-selectors.json
```

---

## 模组7故障排除

### OAM问题

#### 问题：OAM服务不可用
**症状**：OAM Sink创建失败
**解决方案**：
```bash
# 检查OAM服务可用性
aws oam list-sinks --region us-east-1
aws oam list-sinks --region us-west-2

# OAM仅在特定区域可用
# 检查AWS文档获取支持的区域列表
```

### StackSet问题

#### 问题：StackSet权限错误
**症状**：无法创建StackSet或部署失败
**解决方案**：
```bash
# 检查StackSets信任访问
aws organizations list-aws-service-access-for-organization \
  --query 'EnabledServicePrincipals[?ServicePrincipal==`stacksets.cloudformation.amazonaws.com`]'

# 启用信任访问
aws organizations enable-aws-service-access \
  --service-principal stacksets.cloudformation.amazonaws.com

# 检查成员账户的执行角色
# 成员账户需要AWSCloudFormationStackSetExecutionRole
```

#### 问题：StackSet部署到成员账户失败
**症状**：实例状态为FAILED
**解决方案**：
```bash
# 检查失败的实例
aws cloudformation list-stack-instances \
  --stack-set-name <stackset-name> \
  --query 'Summaries[?Status==`FAILED`]'

# 查看失败原因
aws cloudformation describe-stack-instance \
  --stack-set-name <stackset-name> \
  --stack-instance-account <account-id> \
  --stack-instance-region us-east-1

# 重试部署
aws cloudformation create-stack-instances \
  --stack-set-name <stackset-name> \
  --deployment-targets OrganizationalUnitIds=<ou-id> \
  --regions us-east-1
```

### CloudFront监控问题

#### 问题：CloudWatch告警未触发
**症状**：有CloudFront流量但未收到通知
**解决方案**：
```bash
# 检查CloudWatch指标
aws cloudwatch list-metrics \
  --namespace AWS/CloudFront \
  --region us-east-1

# 检查告警状态
aws cloudwatch describe-alarms \
  --alarm-names <alarm-name>

# 手动触发告警测试
aws cloudwatch set-alarm-state \
  --alarm-name <alarm-name> \
  --state-value ALARM \
  --state-reason "Manual test"
```

#### 问题：Telegram通知失败
**症状**：Lambda执行成功但无Telegram消息
**解决方案**：
```bash
# 检查Lambda环境变量
aws lambda get-function-configuration \
  --function-name <function-name> \
  --query 'Environment.Variables'

# 测试Telegram Bot连接
curl -X GET "https://api.telegram.org/bot<BOT_TOKEN>/getMe"

# 测试发送消息
curl -X POST "https://api.telegram.org/bot<BOT_TOKEN>/sendMessage" \
  -H "Content-Type: application/json" \
  -d '{"chat_id": "<GROUP_ID>", "text": "Test message"}'
```

---

## 系统级问题

### 区域问题

#### 问题：服务在错误区域部署
**症状**：某些服务创建失败
**解决方案**：
```bash
# 检查当前区域
aws configure get region
echo $AWS_DEFAULT_REGION

# 服务区域要求：
# - CUR导出：必须us-east-1
# - BillingConductor：通常us-east-1
# - OAM：检查支持的区域
# - 其他服务：通常支持所有区域

# 设置正确区域
export AWS_DEFAULT_REGION=us-east-1
aws configure set region us-east-1
```

### 依赖关系问题

#### 问题：模组依赖未满足
**症状**：后续模组部署失败，缺少参数
**解决方案**：
```bash
# 检查测试变量文件
cat /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

# 重新加载变量
source /Users/di.miao/Work/payer-setup/deployment-testing/test-variables.sh

# 手动获取缺失的参数
# 例如：BillingGroup ARN
aws cloudformation describe-stacks \
  --stack-name <billing-stack> \
  --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' \
  --output text
```

### 性能问题

#### 问题：部署时间过长
**症状**：CloudFormation栈创建超过预期时间
**解决方案**：
```bash
# 检查资源创建进度
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --query 'StackEvents[-10:].{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}'

# 检查Lambda函数超时设置
aws lambda get-function-configuration \
  --function-name <function-name> \
  --query 'Timeout'

# 监控特定资源类型
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --query 'StackEvents[?ResourceType==`AWS::Lambda::Function`]'
```

---

## 性能优化

### 并行部署优化

```bash
# 可以并行部署的模组：
# 模组3和模组4（两个CUR模组）

# 同时启动两个模组的部署
./scripts/deploy-single.sh 3 --billing-group-arn $BILLING_GROUP_ARN &
./scripts/deploy-single.sh 4 &

# 等待两个模组完成
wait
```

### 资源清理优化

```bash
# 创建清理所有测试资源的脚本
cat > cleanup-all.sh << 'EOF'
#!/bin/bash

# 删除顺序与创建相反
echo "清理所有模组资源..."

# 模组7 (先删除StackSet)
if [ -n "$MODULE7_STACK_NAME" ]; then
  aws cloudformation delete-stack-instances \
    --stack-set-name "$STACKSET_NAME" \
    --deployment-targets OrganizationalUnitIds="$NORMAL_OU_ID" \
    --regions "us-east-1" --retain-stacks false
  
  sleep 120
  
  aws cloudformation delete-stack-set --stack-set-name "$STACKSET_NAME"
  aws cloudformation delete-stack --stack-name "$MODULE7_STACK_NAME"
fi

# 模组6-1 (其他模组)
for MODULE in 6 5 4 3 2 1; do
  STACK_VAR="MODULE${MODULE}_STACK_NAME"
  STACK_NAME=$(eval echo \$$STACK_VAR)
  if [ -n "$STACK_NAME" ]; then
    echo "删除模组$MODULE: $STACK_NAME"
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
  fi
done

echo "清理完成"
EOF

chmod +x cleanup-all.sh
```

### 监控和日志优化

```bash
# 创建统一的日志查看脚本
cat > view-logs.sh << 'EOF'
#!/bin/bash

LOG_GROUPS=(
  "/aws/lambda/AttachSCPToOU"
  "/aws/lambda/CreateAccountAndBillingGroup"
  "/aws/lambda/CreateCURExport"
  "/aws/lambda/CreateRISPCURExport"
  "/aws/lambda/CreateAthenaEnvironment"
  "/aws/lambda/AccountAutoMover"
  "/aws/lambda/CloudTrailManager"
  "/aws/lambda/${PAYER_NAME}-CloudFront-Alert"
  "/aws/lambda/${PAYER_NAME}-OAM-Setup"
)

for LOG_GROUP in "${LOG_GROUPS[@]}"; do
  echo "=== $LOG_GROUP ==="
  aws logs filter-log-events \
    --log-group-name "$LOG_GROUP" \
    --start-time $(date -d '1 hour ago' +%s)000 \
    --query 'events[].message' \
    --output text \
    2>/dev/null || echo "日志组不存在或无权限"
  echo ""
done
EOF

chmod +x view-logs.sh
```

---

## 联系支持

### 获取支持信息

在联系支持前，请收集以下信息：

```bash
# 创建支持信息收集脚本
cat > collect-support-info.sh << 'EOF'
#!/bin/bash

SUPPORT_DIR="support-info-$(date +%Y%m%d_%H%M%S)"
mkdir -p $SUPPORT_DIR

echo "收集支持信息..."

# AWS环境信息
aws sts get-caller-identity > $SUPPORT_DIR/caller-identity.json
aws configure list > $SUPPORT_DIR/aws-config.txt
aws organizations describe-organization > $SUPPORT_DIR/organization.json 2>/dev/null

# CloudFormation栈信息
aws cloudformation list-stacks \
  --query 'StackSummaries[?contains(StackName, `payer`)].{Name:StackName,Status:StackStatus}' \
  --output table > $SUPPORT_DIR/stacks-status.txt

# 错误日志
aws cloudformation describe-stack-events \
  --stack-name <problem-stack> \
  --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
  --output table > $SUPPORT_DIR/stack-errors.txt 2>/dev/null

echo "支持信息已保存到 $SUPPORT_DIR/"
echo "请将此目录打包发送给支持团队"

tar -czf "${SUPPORT_DIR}.tar.gz" $SUPPORT_DIR/
echo "已创建压缩包: ${SUPPORT_DIR}.tar.gz"
EOF

chmod +x collect-support-info.sh
```

### 常见支持渠道

1. **内部文档**：查看`docs/`目录下的详细文档
2. **GitHub Issues**：如果项目开源，提交issue
3. **AWS支持**：对于AWS服务相关问题
4. **团队内部**：联系项目维护者

---

## 预防措施

### 部署前检查清单

```bash
# 创建部署前检查脚本
cat > pre-deployment-check.sh << 'EOF'
#!/bin/bash

echo "=== AWS Payer Automation 部署前检查 ==="

# 1. AWS CLI配置
echo "1. 检查AWS CLI配置..."
aws sts get-caller-identity || { echo "❌ AWS CLI未配置"; exit 1; }

# 2. 区域检查
REGION=$(aws configure get region)
if [ "$REGION" != "us-east-1" ]; then
  echo "⚠️  当前区域: $REGION, CUR需要us-east-1"
fi

# 3. Organizations权限
echo "2. 检查Organizations权限..."
aws organizations describe-organization > /dev/null || { echo "❌ Organizations权限不足"; exit 1; }

# 4. 必需服务检查
echo "3. 检查必需服务权限..."
SERVICES=("billingconductor" "cur" "glue" "events" "cloudtrail" "oam")
for SERVICE in "${SERVICES[@]}"; do
  case $SERVICE in
    "billingconductor")
      aws billingconductor list-billing-groups --region us-east-1 > /dev/null 2>&1 && echo "✅ BillingConductor" || echo "⚠️ BillingConductor"
      ;;
    "cur")
      aws cur describe-report-definitions --region us-east-1 > /dev/null 2>&1 && echo "✅ CUR" || echo "⚠️ CUR"
      ;;
    "glue")
      aws glue get-databases --region us-east-1 > /dev/null 2>&1 && echo "✅ Glue" || echo "⚠️ Glue"
      ;;
    "events")
      aws events list-rules --region us-east-1 > /dev/null 2>&1 && echo "✅ EventBridge" || echo "⚠️ EventBridge"
      ;;
    "cloudtrail")
      aws cloudtrail describe-trails > /dev/null 2>&1 && echo "✅ CloudTrail" || echo "⚠️ CloudTrail"
      ;;
    "oam")
      aws oam list-sinks --region us-east-1 > /dev/null 2>&1 && echo "✅ OAM" || echo "⚠️ OAM"
      ;;
  esac
done

# 5. 模板验证
echo "4. 验证CloudFormation模板..."
./scripts/validate.sh || { echo "❌ 模板验证失败"; exit 1; }

echo "✅ 部署前检查完成"
EOF

chmod +x pre-deployment-check.sh
```

这个故障排除指南涵盖了所有7个模组的常见问题和解决方案。建议在遇到问题时：

1. 先查看对应模组的故障排除部分
2. 检查通用问题部分
3. 使用提供的诊断脚本
4. 必要时收集支持信息

每个模组的测试文档中也包含了特定的故障排除部分，可以结合使用。