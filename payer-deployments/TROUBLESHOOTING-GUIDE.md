# Payer部署故障排除指南

**版本**: 1.1  
**创建时间**: 2025-07-24  
**最后更新**: 2025-07-24 20:45 JST  
**基于**: Elite-new11部署实战经验 + 版本管理系统集成

---

## 🎯 使用本指南

当Payer部署遇到问题时，按照以下步骤进行故障排除：

1. **检查版本** - 确认使用v1稳定版本，避免已知问题
2. **识别错误类型** - 根据错误信息分类
3. **查找解决方案** - 使用本指南的具体修复步骤  
4. **执行修复** - 按照步骤执行
5. **验证结果** - 确认问题已解决
6. **更新文档** - 记录新发现的问题

## 🔄 版本管理系统预防 (2025-07-24)

**重要提醒**: 大多数已知问题已在v1版本中修复！

### ✅ v1版本已修复的问题
- **Module 5**: Lambda代码过长问题 (28,869字符 → 4KB)
- **Module 6**: Lambda函数名长度超限问题 (>64字符 → ≤64字符)
- **所有核心模块**: Elite-new11生产验证通过

### 🚀 推荐故障排除流程
```bash
# 1. 首先验证使用的是v1版本
../aws-payer-automation/deployment-scripts/version-management.sh list-versions

# 2. 如果使用v0版本，立即切换到v1
../aws-payer-automation/deployment-scripts/version-management.sh deploy <module> v1 <stack-name>

# 3. 批量重新部署使用v1版本
../aws-payer-automation/deployment-scripts/version-management.sh deploy-all v1 <payer-name>
```

---

## 🚨 常见部署错误速查

### 错误分类快速索引

| 错误类型 | 关键词 | v1修复状态 | 跳转 |
|----------|--------|------------|------|
| Lambda相关 | `Could not unzip`, `FunctionName`, `Member must have length` | ✅ **已修复** | [Lambda错误](#lambda-related-errors) |
| CloudFormation | `CREATE_FAILED`, `ROLLBACK_COMPLETE` | ⚠️ 部分修复 | [CloudFormation错误](#cloudformation-errors) |
| 权限相关 | `AccessDenied`, `UnauthorizedOperation` | ➖ 环境相关 | [权限错误](#permission-errors) |
| 资源限制 | `LimitExceeded`, `InsufficientCapacity` | ➖ AWS限制 | [资源限制](#resource-limits) |
| BillingConductor | `BillingConductor`, `InvalidBillingGroup` | ➖ 服务相关 | [计费错误](#billing-errors) |
| 版本相关 | `v0`, `deprecated`, 旧模板路径 | 🆕 **预防** | [版本问题](#version-issues) |

---

## 🔧 Lambda相关错误 {#lambda-related-errors}

### 错误1: Lambda代码无法解压 ✅ v1已修复
**错误信息**:
```
Could not unzip uploaded file. Please check your file, then try to upload again.
```

**原因分析**:
- 内联Lambda代码超过CloudFormation ZipFile限制（约4KB）
- 代码中包含特殊字符导致压缩失败
- CloudFormation处理内联代码时出现编码问题

**✅ v1版本解决方案（推荐）**:
```bash
# 使用v1版本自动修复（推荐方式）
../aws-payer-automation/deployment-scripts/version-management.sh deploy 05-athena-setup v1 "${STACK_PREFIX}-${PAYER_NAME}-athena-setup-${TIMESTAMP}"

# 或使用current符号链接（自动指向v1）
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-${PAYER_NAME}-athena-setup-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/current/05-athena-setup/athena_setup.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameters [参数列表]
```

**🔧 手动修复方案（不推荐）**:

**步骤1**: 确认受影响模块
```bash
# 检查失败的栈
aws cloudformation describe-stack-events \
  --stack-name <STACK_NAME> \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

**步骤2**: 使用v1修复版模板
```bash
# 使用版本化路径
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-${PAYER_NAME}-athena-setup-fixed-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/versions/v1/05-athena-setup/athena_setup.yaml \
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

### 错误2: Lambda函数名长度超限 ✅ v1已修复
**错误信息**:
```
Value 'payer-Elite-new11-account-management-1753341764-CloudTrailManager' at 'functionName' failed to satisfy constraint: Member must have length less than or equal to 64
```

**原因分析**:
- 使用`!Sub "${AWS::StackName}-FunctionName"`导致名称过长
- 栈名称包含长Payer名称和时间戳

**✅ v1版本解决方案（推荐）**:
```bash
# 使用v1版本自动修复（推荐方式）
../aws-payer-automation/deployment-scripts/version-management.sh deploy 06-account-auto-management v1 "${STACK_PREFIX}-${PAYER_NAME}-account-management-${TIMESTAMP}"

# 或使用current符号链接（自动指向v1）
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-${PAYER_NAME}-account-management-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/current/06-account-auto-management/account_auto_move.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameters ParameterKey=NormalOUId,ParameterValue=${NORMAL_OU_ID}
```

**🔧 手动修复方案（不推荐）**:

**步骤1**: 使用v1修复版模板
```bash
# 使用版本化路径
aws cloudformation create-stack \
  --stack-name "${STACK_PREFIX}-${PAYER_NAME}-account-management-fixed-${TIMESTAMP}" \
  --template-body file://$PROJECT_PATH/templates/versions/v1/06-account-auto-management/account_auto_move.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --parameters ParameterKey=NormalOUId,ParameterValue=${NORMAL_OU_ID}
```

**步骤2**: 验证函数名（v1版本输出示例）
```bash
# 检查创建的Lambda函数（v1版本生成的名称格式：Elite-Elite-CTManager）
aws lambda list-functions \
  --region us-east-1 \
  --query 'Functions[?contains(FunctionName, `Elite`)].FunctionName'

# 预期输出：["Elite-Elite-CTManager"] （≤64字符）
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

## 🆕 版本相关问题 {#version-issues}

### 问题1: 使用了deprecated的v0版本
**症状**: 
- Lambda代码过长错误仍然出现
- Lambda函数名长度超限错误仍然出现
- 使用了旧的模板路径

**诊断**:
```bash
# 检查当前使用的版本
../aws-payer-automation/deployment-scripts/version-management.sh list-versions

# 检查current符号链接指向
ls -la ../aws-payer-automation/templates/current/

# 验证模板路径
file ../aws-payer-automation/templates/current/05-athena-setup/athena_setup.yaml
```

**解决方案**:
```bash
# 1. 更新到v1版本
../aws-payer-automation/deployment-scripts/version-management.sh update-current v1

# 2. 重新部署失败的模块
../aws-payer-automation/deployment-scripts/version-management.sh deploy 05-athena-setup v1 <new-stack-name>
../aws-payer-automation/deployment-scripts/version-management.sh deploy 06-account-auto-management v1 <new-stack-name>

# 3. 批量重新部署
../aws-payer-automation/deployment-scripts/version-management.sh deploy-all v1 <payer-name>
```

### 问题2: 符号链接失效
**症状**: 
```
ls: cannot access '../aws-payer-automation/templates/current/': No such file or directory
```

**解决方案**:
```bash
# 重新创建符号链接
cd ../aws-payer-automation/templates
rm -rf current/
../deployment-scripts/version-management.sh update-current v1

# 验证修复
ls -la current/
```

### 问题3: 版本注册表损坏
**症状**: JSON解析错误

**解决方案**:
```bash
# 验证JSON格式（应该无错误输出）
jq . ../aws-payer-automation/templates/version-registry.json

# 如果损坏，可以重新生成基础注册表（需要手动修复完整内容）
echo '{"version":"1.0","current_version":"v1","versions":{}}' > ../aws-payer-automation/templates/version-registry.json
```

---

**维护说明**: 本指南基于实际部署经验持续更新。遇到新问题请及时补充。

**最后更新**: 2025-07-24 20:50 JST  
**版本**: 1.1  
**贡献者**: Claude Code AI Assistant  
**变更记录**: 2025-07-24 - 集成版本管理系统，更新所有错误解决方案