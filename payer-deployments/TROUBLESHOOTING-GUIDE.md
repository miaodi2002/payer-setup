# Payer部署故障排除指南

**版本**: 1.0  
**创建时间**: 2025-07-24  
**基于**: Elite-new11部署实战经验

---

## 🎯 使用本指南

当Payer部署遇到问题时，按照以下步骤进行故障排除：

1. **识别错误类型** - 根据错误信息分类
2. **查找解决方案** - 使用本指南的具体修复步骤  
3. **执行修复** - 按照步骤执行
4. **验证结果** - 确认问题已解决
5. **更新文档** - 记录新发现的问题

---

## 🚨 常见部署错误速查

### 错误分类快速索引

| 错误类型 | 关键词 | 跳转 |
|----------|--------|------|
| Lambda相关 | `Could not unzip`, `FunctionName`, `Member must have length` | [Lambda错误](#lambda-related-errors) |
| CloudFormation | `CREATE_FAILED`, `ROLLBACK_COMPLETE` | [CloudFormation错误](#cloudformation-errors) |
| 权限相关 | `AccessDenied`, `UnauthorizedOperation` | [权限错误](#permission-errors) |
| 资源限制 | `LimitExceeded`, `InsufficientCapacity` | [资源限制](#resource-limits) |
| BillingConductor | `BillingConductor`, `InvalidBillingGroup` | [计费错误](#billing-errors) |

---

## 🔧 Lambda相关错误 {#lambda-related-errors}

### 错误1: Lambda代码无法解压
**错误信息**:
```
Could not unzip uploaded file. Please check your file, then try to upload again.
```

**原因分析**:
- 内联Lambda代码超过CloudFormation ZipFile限制（约4KB）
- 代码中包含特殊字符导致压缩失败
- CloudFormation处理内联代码时出现编码问题

**解决方案**:

**步骤1**: 确认受影响模块
```bash
# 检查失败的栈
aws cloudformation describe-stack-events \
  --stack-name <STACK_NAME> \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

**步骤2**: 使用修复版模板
```bash
# 对于Module 5
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-${PAYER_NAME}-athena-setup-fixed-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/05-athena-setup/athena_setup_fixed.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameters [参数列表]
```

**步骤3**: 验证修复
```bash
# 检查新栈状态
aws cloudformation describe-stacks \
  --stack-name <NEW_STACK_NAME> \
  --query 'Stacks[0].StackStatus'
```

### 错误2: Lambda函数名长度超限
**错误信息**:
```
Value 'payer-Elite-new11-account-management-1753341764-CloudTrailManager' at 'functionName' failed to satisfy constraint: Member must have length less than or equal to 64
```

**原因分析**:
- 使用`!Sub "${AWS::StackName}-FunctionName"`导致名称过长
- 栈名称包含长Payer名称和时间戳

**解决方案**:

**步骤1**: 使用修复版模板
```bash
# 对于Module 6
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-${PAYER_NAME}-account-management-fixed-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/06-account-auto-management/account_auto_move_fixed_v2.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameters ParameterKey=NormalOUId,ParameterValue=${NORMAL_OU_ID}
```

**步骤2**: 验证函数名
```bash
# 检查创建的Lambda函数
aws lambda list-functions \
  --region us-east-1 \
  --query 'Functions[?contains(FunctionName, `Elite`)].FunctionName'
```

---

## ☁️ CloudFormation错误 {#cloudformation-errors}

### 错误1: 栈创建失败并回滚
**症状**: 栈状态显示`ROLLBACK_COMPLETE`

**诊断步骤**:
```bash
# 1. 查看失败事件
aws cloudformation describe-stack-events \
  --stack-name <STACK_NAME> \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason,Timestamp]' \
  --output table

# 2. 检查具体资源失败原因
aws cloudformation describe-stack-resources \
  --stack-name <STACK_NAME> \
  --region us-east-1 \
  --query 'StackResources[?ResourceStatus==`CREATE_FAILED`]'
```

**通用解决方案**:
1. **删除失败栈**: `aws cloudformation delete-stack --stack-name <STACK_NAME>`
2. **检查权限**: 确认当前用户有所需权限
3. **验证模板**: 使用正确的模板版本
4. **重新部署**: 使用修复版模板

---

## 🔐 权限错误 {#permission-errors}

### 错误1: BillingConductor访问被拒绝
**错误信息**:
```
AccessDeniedException: User is not authorized to perform billingconductor:ListBillingGroups
```

**解决方案**:
```bash
# 1. 验证账户是否为Payer账户
aws organizations describe-organization --query 'Organization.MasterAccountId'

# 2. 检查BillingConductor服务状态
aws billingconductor list-billing-groups --region us-east-1

# 3. 如果失败，联系AWS支持启用BillingConductor
```

### 错误2: Organizations权限不足
**错误信息**:
```
AWSOrganizationsNotInUseException: Your account is not a member of an organization
```

**解决方案**:
```bash
# 1. 创建Organizations（如果账户是独立的）
aws organizations create-organization --feature-set ALL

# 2. 验证创建成功
aws organizations describe-organization
```

---

## 📊 资源限制 {#resource-limits}

### 错误1: Lambda并发限制
**解决方案**:
```bash
# 检查当前限制
aws lambda get-account-settings --region us-east-1

# 如需提高限制，通过AWS支持案例申请
```

### 错误2: CloudFormation栈数量限制
**解决方案**:
```bash
# 清理不需要的测试栈
aws cloudformation list-stacks \
  --stack-status-filter DELETE_COMPLETE ROLLBACK_COMPLETE \
  --query 'StackSummaries[?StackStatus==`ROLLBACK_COMPLETE`].StackName'
```

---

## 💰 计费错误 {#billing-errors}

### 错误1: BillingGroup创建失败
**诊断**:
```bash
# 检查现有BillingGroups
aws billingconductor list-billing-groups --region us-east-1

# 检查关联账户
aws billingconductor list-account-associations --region us-east-1
```

**解决**:
- 确认账户类型为Payer账户
- 验证BillingConductor服务已启用
- 检查是否达到BillingGroup数量限制

---

## 🔍 高级诊断技巧

### 1. CloudWatch日志分析
```bash
# 查看Lambda函数日志
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/"

# 获取最新日志
aws logs get-log-events \
  --log-group-name "/aws/lambda/<FUNCTION_NAME>" \
  --log-stream-name "<STREAM_NAME>"
```

### 2. 资源依赖关系追踪
```bash
# 查看栈资源
aws cloudformation describe-stack-resources \
  --stack-name <STACK_NAME> \
  --query 'StackResources[*].[LogicalResourceId,ResourceType,ResourceStatus]' \
  --output table
```

### 3. 区域特定问题
```bash
# 确认操作区域
aws configure get region
# 必须是 us-east-1 用于BillingConductor
```

---

## 🚑 紧急修复流程

### 生产环境部署失败
1. **立即停止**: 停止所有正在进行的部署
2. **评估影响**: 确认已创建的资源状态
3. **保护数据**: 确保关键数据（如新账户）安全
4. **回滚策略**: 使用预定义的回滚脚本
5. **根因分析**: 详细分析失败原因
6. **修复验证**: 在测试环境验证修复方案

### 紧急联系信息
- **AWS支持**: 通过AWS控制台创建支持案例
- **内部升级**: 联系系统管理员
- **文档更新**: 记录新发现的问题和解决方案

---

## 📝 问题报告模板

发现新问题时，请使用以下模板记录：

```markdown
## 新问题: [简短描述]

**发现时间**: YYYY-MM-DD HH:MM
**影响模块**: Module X
**错误信息**: 
```
[完整错误信息]
```

**环境信息**:
- AWS区域: us-east-1
- 账户ID: [ACCOUNT_ID]
- Payer名称: [PAYER_NAME]

**重现步骤**:
1. [步骤1]
2. [步骤2]

**解决方案**:
[详细解决步骤]

**验证方法**:
[如何确认问题已解决]
```

---

**维护说明**: 本指南基于实际部署经验持续更新。遇到新问题请及时补充。

**最后更新**: 2025-07-24 18:40 JST  
**版本**: 1.0  
**贡献者**: Claude Code AI Assistant