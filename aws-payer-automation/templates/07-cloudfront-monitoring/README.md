# Module 7: CloudFront跨账户监控系统

## 概述

Module 7实现CloudFront流量的跨账户监控系统，通过AWS Observability Access Manager (OAM)集中监控所有成员账户的CloudFront流量，并在超过阈值时通过Telegram发送告警通知。

## 功能特点

### 核心功能
- **智能OAM设置**: 自动检测并配置AWS OAM基础设施
- **跨账户监控**: 在Payer账户集中监控所有成员账户的CloudFront流量
- **实时告警**: 超过阈值时立即发送Telegram通知
- **具体账户识别**: 告警中明确显示哪些账户超过流量限制

### 监控指标
- **CloudFront BytesDownloaded**: 所有分发的下载字节数
- **监控周期**: 15分钟滚动窗口
- **默认阈值**: 100MB（可配置）

### 安全特性
- 最小权限IAM角色设计
- 自动账户发现通过Organizations API
- Telegram Bot Token等敏感信息通过环境变量管理

## 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                   Payer账户 (Management)                    │
│                                                             │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │    OAM Sink        │    │   CloudWatch Alarm  │        │
│  │   (数据接收)         │    │   (流量监控)         │        │
│  └─────────────────────┘    └─────────────────────┘        │
│             ▲                          │                   │
│             │                          ▼                   │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │ CloudFormation     │    │    SNS Topic        │        │
│  │ StackSet           │    └─────────────────────┘        │
│  └─────────────────────┘              │                   │
│                                        ▼                   │
│                              ┌─────────────────────┐        │
│                              │  Alert Lambda      │        │
│                              │  (Telegram通知)     │        │
│                              └─────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┼─────────────────────────────┐
│          成员账户1          │          成员账户N          │
│                             │                             │
│  ┌─────────────────────┐    │    ┌─────────────────────┐  │
│  │    OAM Link        │────┼────│    OAM Link        │  │
│  │                     │    │    │                     │  │
│  └─────────────────────┘    │    └─────────────────────┘  │
│  ┌─────────────────────┐    │    ┌─────────────────────┐  │
│  │   CloudFront       │    │    │   CloudFront       │  │
│  │   分发数据           │    │    │   分发数据           │  │
│  └─────────────────────┘    │    └─────────────────────┘  │
└─────────────────────────────┼─────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Telegram Bot    │
                    │     告警通知       │
                    └───────────────────┘
```

## 创建的资源

### OAM基础设施
- **MonitoringSink**: 在Payer账户接收所有成员账户数据
- **OAM Link StackSet**: 通过CloudFormation StackSet部署到成员账户的OAM Links

### 监控告警
- **CloudFrontTrafficAlarm**: 监控总CloudFront流量的CloudWatch告警
- **CloudFrontAlarmTopic**: SNS主题用于告警通知
- **CloudFrontAlertFunction**: 处理告警并发送Telegram通知的Lambda函数

### IAM权限
- **CloudFrontAlertRole**: 包含CloudWatch查询权限

## 部署参数

### 必需参数
- **PayerName**: Payer名称（动态获取Master Account名称）

### 自动发现
- **成员账户**: 自动从AWS Organizations发现所有活跃的成员账户

### 可选参数
- **CloudFrontThresholdMB**: 流量阈值（默认100MB）
- **TelegramGroupId**: Telegram群组ID（默认-862835857）
- **TelegramApiEndpoint**: Telegram API地址（默认已配置）

### 输出
- **MonitoringSinkArn**: OAM Sink的ARN
- **CloudFrontAlarmName**: CloudWatch告警名称
- **AlertFunctionArn**: 告警Lambda函数ARN
- **PayerName**: Payer名称（透传）
- **ThresholdMB**: 配置的阈值

## 使用方法

### 两步部署过程

#### 第一步：部署Payer账户基础设施
```bash
# 获取Master Account名称作为Payer名称
MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
PAYER_NAME=$(aws organizations describe-account --account-id $MASTER_ACCOUNT_ID --query 'Account.Name' --output text)

# 基本部署（成员账户自动发现）
./scripts/deploy-single.sh 7 \
  --payer-name "$PAYER_NAME"

# 自定义阈值和群组
./scripts/deploy-single.sh 7 \
  --payer-name "$PAYER_NAME" \
  --threshold-mb 150 \
  --telegram-group-id -123456789
```

#### 第二步：使用StackSet部署OAM Links
```bash
# 确保已激活CloudFormation StackSets与AWS Organizations的可信访问
aws organizations enable-aws-service-access \
  --service-principal member.org.stacksets.cloudformation.amazonaws.com

# 获取OAM Sink ARN
SINK_ARN=$(aws cloudformation describe-stacks \
  --stack-name payer-cloudfront-monitoring-* \
  --query 'Stacks[0].Outputs[?OutputKey==`MonitoringSinkArn`].OutputValue' \
  --output text)

# 创建StackSet（使用SERVICE_MANAGED权限模型）
aws cloudformation create-stack-set \
  --stack-set-name "${PAYER_NAME}-OAM-Links" \
  --template-body file://templates/07-cloudfront-monitoring/oam-link-stackset.yaml \
  --parameters ParameterKey=OAMSinkArn,ParameterValue=$SINK_ARN ParameterKey=PayerName,ParameterValue="$PAYER_NAME" \
  --capabilities CAPABILITY_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false

# 部署到Normal OU
NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name payer-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text)

aws cloudformation create-stack-instances \
  --stack-set-name "${PAYER_NAME}-OAM-Links" \
  --deployment-targets OrganizationalUnitIds=$NORMAL_OU_ID \
  --regions us-east-1
```

### 验证部署
```bash
# 检查OAM Sink状态
aws oam list-sinks

# 检查成员账户的OAM Link
aws oam list-links --account-id 123456789012

# 检查CloudWatch告警
aws cloudwatch describe-alarms --alarm-names "${PAYER_NAME}_CloudFront_Cross_Account_Traffic"

# 查看Lambda函数
aws lambda get-function --function-name ${PAYER_NAME}-OAM-Setup
aws lambda get-function --function-name ${PAYER_NAME}-CloudFront-Alert
```

## 监控和日志

### CloudWatch日志
- **OAM设置日志**: `/aws/lambda/{PayerName}-OAM-Setup`
- **告警处理日志**: `/aws/lambda/{PayerName}-CloudFront-Alert`

### 日志示例

#### OAM设置日志
```
[INFO] Starting OAM setup process...
[INFO] Setting up OAM for account: 123456789012
[INFO] Successfully created OAM Link for account 123456789012
[INFO] OAM setup completed for 3 accounts
```

#### 告警处理日志
```
[INFO] Processing alarm: ${PAYER_NAME}_CloudFront_Cross_Account_Traffic, State: ALARM
[INFO] Found 2 accounts exceeding threshold:
[INFO]   - Account 123456789012: 156.7 MB
[INFO]   - Account 234567890123: 134.2 MB
[INFO] Telegram API Response: 200 - {"status":"success"}
```

### 监控命令
```bash
# 查看最近的OAM设置活动
aws logs filter-log-events \
  --log-group-name /aws/lambda/${PAYER_NAME}-OAM-Setup \
  --start-time $(date -d '1 hour ago' +%s)000

# 查看最近的告警活动
aws logs filter-log-events \
  --log-group-name /aws/lambda/${PAYER_NAME}-CloudFront-Alert \
  --start-time $(date -d '1 hour ago' +%s)000

# 检查CloudWatch指标
aws cloudwatch get-metric-data \
  --metric-data-queries file://metric-query.json \
  --start-time $(date -d '1 hour ago' --iso-8601) \
  --end-time $(date --iso-8601)
```

## Telegram告警格式

### 告警消息示例
```
🚨 CloudFront流量告警 - ${PAYER_NAME}

📊 超量账户详情:
┌─────────────────────────
│ 1. 账户: 123456789012
│    用量: 156.7 MB
│    超出: +56.7%
├─────────────────────────
│ 2. 账户: 234567890123
│    用量: 134.2 MB
│    超出: +34.2%
└─────────────────────────

📈 告警信息:
• 告警名称: ${PAYER_NAME}_CloudFront_Cross_Account_Traffic
• 设定阈值: 100 MB
• 监控周期: 15分钟
• 告警时间: 2024-01-15 14:30:00 UTC

⚠️ 建议立即检查CloudFront使用情况

🔗 快速链接:
• CloudFront: https://console.aws.amazon.com/cloudfront
• CloudWatch: https://console.aws.amazon.com/cloudwatch
```

## 故障排除

### 常见问题

1. **OAM Link创建失败**
   - 检查OrganizationAccountAccessRole是否存在
   - 验证跨账户权限配置
   - 查看OAM Setup Lambda日志

2. **告警未触发**
   - 确认CloudFront有实际流量
   - 检查OAM数据是否正常同步
   - 验证CloudWatch告警配置

3. **Telegram通知失败**
   - 检查API端点是否可访问
   - 验证群组ID是否正确
   - 查看Alert Lambda日志

### 权限验证
```bash
# 测试OAM权限
aws oam list-sinks
aws sts assume-role --role-arn arn:aws:iam::ACCOUNT:role/OrganizationAccountAccessRole --role-session-name test

# 测试CloudWatch权限
aws cloudwatch list-metrics --namespace AWS/CloudFront

# 测试Lambda权限
aws lambda list-functions --function-version ALL
```

### 手动测试
```bash
# 手动触发OAM设置
aws lambda invoke \
  --function-name ${PAYER_NAME}-OAM-Setup \
  --payload '{}' \
  response.json

# 模拟告警测试
aws lambda invoke \
  --function-name ${PAYER_NAME}-CloudFront-Alert \
  --payload file://test-alarm.json \
  response.json
```

## 安全注意事项

### IAM权限
- Lambda角色遵循最小权限原则
- 跨账户访问仅限于OrganizationAccountAccessRole
- OAM权限限制在监控数据读取

### 数据保护
- 敏感配置通过环境变量管理
- Telegram API调用使用HTTPS
- CloudWatch日志包含详细审计信息

### 访问控制
- OAM Sink策略限制资源类型
- Lambda函数访问限制在特定资源
- 告警数据不包含敏感业务信息

## 集成说明

### 与其他模块的关系
- **独立运行**: 不依赖其他模块的运行时状态
- **可选集成**: 可以从Module 1自动发现Organizations成员账户
- **扩展性**: 支持添加更多监控指标和通知渠道

### 扩展功能
- 支持其他AWS服务监控（ELB、API Gateway等）
- 可以添加更多通知渠道（SNS、Slack等）
- 支持自定义监控阈值和时间窗口

## 成本估算

### AWS服务成本
- **OAM**: 免费（数据传输在同一Region）
- **CloudWatch**: ~$0.30/月（告警 + 指标查询）
- **Lambda**: ~$0.02/月（基于执行次数）
- **SNS**: ~$0.50/月（消息发送）

### 总计
约$0.82/月（基于正常使用量）

## 版本历史

### v1.0
- 基础OAM设置和CloudFront监控
- Telegram Bot集成
- 自动账户超量识别
- 跨账户权限管理
- 智能OAM基础设施检测和设置

## 最佳实践

### 部署建议
1. 首次部署时建议使用较高阈值（如500MB）进行测试
2. 确保所有成员账户的OrganizationAccountAccessRole正常
3. 部署后验证OAM数据流通正常

### 运维建议
1. 定期检查OAM Link状态
2. 监控Lambda函数执行成功率
3. 根据实际使用情况调整阈值
4. 定期更新Telegram群组配置

### 扩展建议
1. 可以添加更多CloudWatch指标监控
2. 考虑集成到现有监控dashboard
3. 可以设置多级阈值告警
4. 支持按时间段的动态阈值调整