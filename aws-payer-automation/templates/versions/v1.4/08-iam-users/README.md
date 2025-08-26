# Module 8: IAM用户初始化系统

## 概述

Module 8实现IAM用户的自动创建和初始化，为Payer部署系统创建必要的系统用户，支持Console登录和预配置权限。

## 功能特点

### 创建的用户
1. **cost_explorer**: 成本分析和计费管理用户
2. **ReadOnly_system**: 系统只读访问用户

### 核心功能
- **自动用户创建**: 使用CloudFormation自动创建IAM用户
- **Console登录配置**: 预设密码和强制首次修改
- **权限预配置**: 直接附加AWS管理策略
- **标准化标签**: 统一的资源标签管理

## 用户详细配置

### cost_explorer用户
**目的**: 成本探索、账单分析和数据查询

**权限策略**:
- `AmazonAthenaFullAccess` - Athena查询服务完整访问
- `AmazonS3FullAccess` - S3存储服务完整访问
- `AWSBillingConductorFullAccess` - 账单指挥中心完整访问
- `AWSGlueSchemaRegistryFullAccess` - Glue模式注册表完整访问
- `AWSOrganizationsReadOnlyAccess` - Organizations只读访问
- `IAMFullAccess` - IAM服务完整访问

### ReadOnly_system用户  
**目的**: 系统监控和只读访问

**权限策略**:
- `ReadOnlyAccess` - 所有AWS服务的只读访问权限

## 登录配置

### Console访问
- **初始密码**: `Password1!`
- **密码策略**: 首次登录必须修改密码
- **访问URL**: `https://{AccountId}.signin.aws.amazon.com/console`

### 安全设置
- 强制密码重置确保首次登录安全
- 使用AWS管理策略确保权限标准化
- 资源标签便于管理和审计

## 部署参数

### 必需参数
- **PayerName**: Payer名称，用于资源标识

### 输出值
- **用户名称**: 创建的IAM用户名
- **用户ARN**: IAM用户的完整ARN
- **登录说明**: Console登录指导信息
- **Payer名称**: 透传的Payer标识

## 使用方法

### 基本部署
```bash
# 使用deploy-single.sh脚本部署
./scripts/deploy-single.sh 8 --payer-name "Elite-new11"

# 或直接使用AWS CLI
aws cloudformation deploy \
  --template-file templates/08-iam-users/iam_users_init.yaml \
  --stack-name payer-Elite-new11-iam-users \
  --parameter-overrides PayerName=Elite-new11 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### 验证部署
```bash
# 查看创建的用户
aws iam list-users --query 'Users[?starts_with(UserName, `cost_explorer`) || starts_with(UserName, `ReadOnly_system`)]'

# 查看用户权限
aws iam list-attached-user-policies --user-name cost_explorer
aws iam list-attached-user-policies --user-name ReadOnly_system

# 验证Console登录配置
aws iam get-login-profile --user-name cost_explorer
aws iam get-login-profile --user-name ReadOnly_system
```

## 部署示例

### Elite-new11部署示例
```bash
# 部署IAM用户模块
aws cloudformation deploy \
  --template-file templates/08-iam-users/iam_users_init.yaml \
  --stack-name payer-Elite-new11-iam-users \
  --parameter-overrides \
    PayerName=Elite-new11 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# 验证部署结果
aws cloudformation describe-stacks \
  --stack-name payer-Elite-new11-iam-users \
  --query 'Stacks[0].Outputs'
```

### 预期输出
```json
[
  {
    "OutputKey": "CostExplorerUserName",
    "OutputValue": "cost_explorer"
  },
  {
    "OutputKey": "ReadOnlySystemUserName", 
    "OutputValue": "ReadOnly_system"
  },
  {
    "OutputKey": "LoginInstructions",
    "OutputValue": "Users created with initial password 'Password1!' and password reset required.\nConsole URL: https://272312908613.signin.aws.amazon.com/console\nUsers: cost_explorer, ReadOnly_system"
  }
]
```

## 首次登录流程

### 1. 获取Console URL
```bash
# 从Stack输出获取登录信息
aws cloudformation describe-stacks \
  --stack-name payer-{PayerName}-iam-users \
  --query 'Stacks[0].Outputs[?OutputKey==`LoginInstructions`].OutputValue' \
  --output text
```

### 2. 用户登录步骤
1. 访问Console URL: `https://{AccountId}.signin.aws.amazon.com/console`
2. 输入用户名: `cost_explorer` 或 `ReadOnly_system`
3. 输入初始密码: `Password1!`
4. 系统将强制要求设置新密码
5. 设置符合密码策略的新密码
6. 完成首次登录配置

## 资源清理

### 删除用户
```bash
# 删除整个Stack
aws cloudformation delete-stack \
  --stack-name payer-{PayerName}-iam-users

# 手动删除用户（如需要）
aws iam delete-login-profile --user-name cost_explorer
aws iam delete-login-profile --user-name ReadOnly_system
aws iam delete-user --user-name cost_explorer
aws iam delete-user --user-name ReadOnly_system
```

## 集成说明

### 与其他模块的关系
- **独立模块**: 不依赖其他模块运行
- **可选部署**: 可以独立部署或跳过
- **标准集成**: 遵循Payer部署系统的标准规范

### 扩展功能
- 可以添加更多预定义用户角色
- 支持自定义权限策略附加
- 可以集成到自动化部署流程

## 最佳实践

### 部署建议
1. 在Master账户中部署此模块
2. 首次部署后立即测试Console登录
3. 确保用户及时修改初始密码
4. 定期审计用户权限和访问日志

### 安全建议
1. 监控用户登录活动
2. 定期检查附加的权限策略
3. 使用CloudTrail审计用户操作
4. 考虑启用MFA（需要手动配置）

## 版本信息

### v1.4集成
- **状态**: 新增模块
- **兼容性**: 与现有模块完全独立
- **部署状态**: 开发完成，待测试验证

### 创建的资源
- 2个IAM用户
- Console登录配置
- 权限策略附加
- 资源标签和输出值

## 故障排除

### 常见问题
1. **权限不足错误**
   - 确保部署账户有IAM用户创建权限
   - 检查`CAPABILITY_NAMED_IAM`参数

2. **密码策略冲突**
   - 检查账户密码策略设置
   - `Password1!`符合AWS默认密码要求

3. **用户已存在错误**
   - 检查是否重复部署
   - 删除现有用户或使用不同Stack名称

### 调试方法
```bash
# 查看CloudFormation事件
aws cloudformation describe-stack-events \
  --stack-name payer-{PayerName}-iam-users

# 检查IAM用户状态
aws iam get-user --user-name cost_explorer
aws iam get-user --user-name ReadOnly_system
```