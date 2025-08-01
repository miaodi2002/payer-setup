# Module 6: 账户自动移动

## 概述

Module 6实现账户自动移动功能，监控AWS Organizations事件，自动将新加入的账户移动到Normal OU并应用SCP限制，防止客户购买预付费RSP服务造成损失。

## 功能特点

### 核心功能
- **事件监控**: 监控CreateAccountResult和AcceptHandshake事件
- **自动移动**: 将新账户自动移动到Normal OU
- **SCP应用**: 自动应用SCP限制防止预付费服务购买
- **错误处理**: 详细的错误处理和日志记录

### 监控事件
1. **CreateAccountResult**: 新账户创建成功
2. **AcceptHandshake**: 邀请账户加入组织

### 安全特性
- 动态OU发现，无硬编码ID
- 详细的移动验证
- 全面的错误处理
- CloudWatch日志记录

## 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Organizations                         │
│                                                             │
│  ┌─────────────┐                    ┌─────────────┐         │
│  │    Root     │ ←── 新账户        │  Normal OU  │         │
│  │             │     自动移动 ──→   │   (目标)    │         │
│  └─────────────┘                    └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────────────────┐
                    │     CloudTrail      │
                    │   (事件监控)         │
                    └─────────────────────┘
                              │
                    ┌─────────────────────┐
                    │    EventBridge      │
                    │   (事件路由)         │
                    └─────────────────────┘
                              │
                    ┌─────────────────────┐
                    │   Lambda Function   │
                    │  (AccountAutoMover) │
                    └─────────────────────┘
```

## 创建的资源

### CloudTrail
- **OrganizationsCloudTrail**: 监控Organizations管理事件
- **CloudTrailS3Bucket**: 存储CloudTrail日志
- **CloudTrailBucketPolicy**: S3存储桶访问策略

### EventBridge规则
- **CreateAccountResultRule**: 捕获账户创建成功事件
- **AcceptHandshakeRule**: 捕获邀请接受事件

### Lambda函数
- **AccountMoverFunction**: 执行账户移动逻辑
- **AccountMoverLambdaRole**: Lambda执行角色
- 权限包括：
  - organizations:MoveAccount
  - organizations:ListRoots
  - organizations:ListOrganizationalUnitsForParent
  - organizations:ListAccountsForParent
  - organizations:DescribeAccount
  - organizations:DescribeOrganizationalUnit

## 部署参数

### 必需参数
- **NormalOUId**: Normal OU的ID（从Module 1获取）

### 输出
- **CloudTrailBucketName**: CloudTrail日志存储桶名称
- **AccountMoverFunctionArn**: Lambda函数ARN
- **NormalOUId**: Normal OU ID（透传）

## 使用方法

### 独立部署
```bash
# 获取Normal OU ID
NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name payer-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text)

# 部署Module 6
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID
```

### 验证部署
```bash
# 检查Lambda函数
aws lambda get-function --function-name AccountAutoMover

# 检查EventBridge规则
aws events list-rules --name-prefix CreateAccountResult

# 查看最近的日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/AccountAutoMover \
  --start-time $(date -d '1 hour ago' +%s)000
```

## 监控和日志

### CloudWatch日志
Lambda函数会记录详细的执行日志：
- 接收到的事件信息
- 账户移动过程
- 成功/失败状态
- 错误详情

### 日志示例
```
[INFO] Received event: {"detail": {"eventName": "CreateAccountResult", ...}}
[INFO] Target Normal OU ID: ou-xxxx-xxxxxxxx
[INFO] CreateAccountResult event - New account: TestAccount (123456789012)
[INFO] Organization Root ID: r-xxxx
[INFO] Account 123456789012 is currently in Root
[INFO] Moving account 123456789012 from r-xxxx to Normal OU ou-xxxx-xxxxxxxx
[SUCCESS] Successfully moved account 123456789012 to Normal OU
[SUCCESS] Verified: Account 123456789012 is now in Normal OU
```

### 监控命令
```bash
# 查看最近的账户移动活动
aws logs filter-log-events \
  --log-group-name /aws/lambda/AccountAutoMover \
  --filter-pattern "Successfully moved account" \
  --start-time $(date -d '24 hours ago' +%s)000

# 查看错误日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/AccountAutoMover \
  --filter-pattern "ERROR" \
  --start-time $(date -d '24 hours ago' +%s)000

# 检查EventBridge规则状态
aws events describe-rule --name CreateAccountResultRule
aws events describe-rule --name AcceptHandshakeRule
```

## 故障排除

### 常见问题

1. **账户移动失败**
   - 检查IAM权限
   - 确认Normal OU ID正确
   - 查看Lambda日志获取详细错误

2. **事件未触发**
   - 确认CloudTrail正在记录
   - 检查EventBridge规则状态
   - 验证Lambda权限配置

3. **权限错误**
   - 确认Lambda角色有正确的Organizations权限
   - 检查跨账户权限（如适用）

4. **AcceptHandshake事件处理错误** ✅ 已修复
   - **问题1**: JSON键大小写错误
     - 错误: 使用`party.get("Type")`和`party.get("Id")`
     - 正确: 使用`party.get("type")`和`party.get("id")`
     - 状态: ✅ 已在`account_auto_move_fixed.yaml`中修复
   
   - **问题2**: Master账户ID字段错误
     - 错误: 使用`event_detail.get("userIdentity", {}).get("accountId")`
     - 正确: 使用`event_detail.get("recipientAccountId")`
     - 原因: 在AcceptHandshake事件中，`userIdentity.accountId`是被邀请账户而非master账户
     - 状态: ✅ 已在`account_auto_move_fixed.yaml`中修复

5. **CloudTrail Manager逻辑错误** ✅ 已修复
   - 问题: CloudTrail Manager在S3存储桶存在时不创建CloudTrail
   - 解决: 修改逻辑为无论存储桶状态如何，如果没有适合的CloudTrail则创建
   - 状态: ✅ 已修复

### 权限验证
```bash
# 测试Organizations权限
aws organizations list-roots
aws organizations list-organizational-units-for-parent --parent-id r-xxxxxxxxxx

# 检查Lambda函数权限
aws lambda get-policy --function-name AccountAutoMover
```

### 手动测试
```bash
# 手动触发Lambda函数进行测试
aws lambda invoke \
  --function-name AccountAutoMover \
  --payload file://test-event.json \
  response.json

# test-event.json示例 - CreateAccountResult
{
  "detail": {
    "eventName": "CreateAccountResult",
    "userIdentity": {
      "accountId": "999999999999"
    },
    "serviceEventDetails": {
      "createAccountStatus": {
        "state": "SUCCEEDED",
        "accountId": "123456789012",
        "accountName": "TestAccount"
      }
    }
  }
}

# test-accepthandshake-event.json示例 - AcceptHandshake
{
  "detail": {
    "eventName": "AcceptHandshake",
    "userIdentity": {
      "accountId": "123456789012"  // This is the invited account, not master
    },
    "recipientAccountId": "999999999999",  // This is the master account
    "responseElements": {
      "handshake": {
        "parties": [
          {"id": "123456789012", "type": "ACCOUNT"},     // Invited account
          {"id": "t4quxjx4cr", "type": "ORGANIZATION"}    // Organization
        ]
      }
    }
  }
}
```

## 安全注意事项

### IAM权限
- Lambda角色遵循最小权限原则
- 只包含必要的Organizations操作权限
- CloudTrail访问限制在特定S3存储桶

### 数据保护
- CloudTrail日志加密存储
- S3存储桶启用版本控制
- 阻止公共访问

### 审计跟踪
- 所有账户移动操作都记录在CloudWatch日志中
- CloudTrail提供完整的审计跟踪
- 可集成到现有监控系统

## AcceptHandshake事件数据结构说明

### 关键字段理解
在AcceptHandshake事件中，数据结构容易混淆：

```json
{
  "detail": {
    "userIdentity": {
      "accountId": "050451385285"      // 被邀请账户ID（不是master）
    },
    "recipientAccountId": "730335480018", // master账户ID（正确字段）
    "responseElements": {
      "handshake": {
        "parties": [
          {"id": "050451385285", "type": "ACCOUNT"},     // 被邀请账户
          {"id": "t4quxjx4cr", "type": "ORGANIZATION"}    // 组织
        ]
      }
    }
  }
}
```

**重要提示**:
- `userIdentity.accountId` = 被邀请账户ID
- `recipientAccountId` = master账户ID
- `parties[].id` 中含有被邀请账户ID
- JSON键是小写：`type`和`id`，不是`Type`和`Id`

## 集成说明

### 与其他模块的依赖
- **依赖Module 1**: 需要Normal OU ID
- **独立运行**: 不依赖其他模块的运行时状态

### 扩展性
- 可以扩展支持其他OU类型
- 可以添加更多的事件类型监控
- 可以集成SNS通知（当前版本已移除）

## 成本估算

### AWS服务成本
- **CloudTrail**: ~$2/月（基于事件数量）
- **Lambda**: ~$0.01/月（基于执行次数）
- **S3存储**: ~$0.5/月（日志存储）
- **EventBridge**: 免费层覆盖大部分使用

### 总计
约$2.5/月（基于正常使用量）

## 修复历史

### v1.1 - 关键AcceptHandshake Bug修复 ✅
**修复日期**: 2025年7月23日

**修复的Bug**:
1. **JSON解析错误**: 修复大小写键问题
   ```python
   # Before (incorrect)
   party_type = party.get("Type")  # Should be "type"
   party_id = party.get("Id")      # Should be "id"
   
   # After (fixed) 
   party_type = party.get("type")
   party_id = party.get("id")
   ```

2. **Master账户ID判断错误**: 修复事件字段选择
   ```python
   # Before (incorrect)
   master_account_id = event_detail.get("userIdentity", {}).get("accountId")
   # This returns invited account ID in AcceptHandshake events
   
   # After (fixed)
   master_account_id = event_detail.get("recipientAccountId")
   # This correctly returns master account ID
   ```

**验证结果**:
- ✅ 账户050451385285成功从Root移动到Normal OU
- ✅ Lambda执行时间: 2.65秒
- ✅ 成功率: 100%

### v1.0
- 基础账户自动移动功能
- CloudTrail事件监控
- 动态OU发现
- 详细错误处理和日志记录
- 移除SNS通知（基于用户反馈）