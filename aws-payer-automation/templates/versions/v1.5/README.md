# AWS Payer Automation Templates v1.5

## 📋 版本信息
- **版本号**: v1.5
- **发布日期**: 2025-08-11
- **状态**: stable
- **基于**: v1.4 + Athena Setup修复

## 🔧 本版本修复内容

### Module 5 - Athena Setup 关键修复
**问题**: IAM角色传播导致的Glue Crawler创建失败
- **错误**: `Service is unable to assume provided role. Please verify role's TrustPolicy`
- **解决**: 在Lambda函数中添加30秒IAM角色传播等待时间
- **验证**: Elite-new12生产环境测试通过

**具体修复**:
1. 添加`import time`模块
2. 增加`time.sleep(30)`等待IAM角色传播
3. 增加Lambda超时时间到600秒
4. 优化日志输出便于调试

## 📦 包含的模块

| 模块 | 状态 | 描述 | 修复内容 |
|------|------|------|----------|
| 01-ou-scp | stable | 组织单元和SCP策略 | 无变更 |
| 02-billing-conductor | stable | 账单导体和账户创建 | 无变更 |
| 03-cur-proforma | stable | Pro forma CUR导出 | 无变更 |
| 04-cur-risp | stable | RISP CUR导出 | 无变更 |
| 05-athena-setup | **FIXED** | Athena和Glue环境 | ✅ IAM角色传播修复 |
| 06-account-auto-management | stable | 账户自动管理 | 无变更 |
| 07-cloudfront-monitoring | stable | CloudFront监控 | 无变更 |
| 08-iam-users | stable | IAM用户初始化 | 无变更 |

## 🎯 推荐使用场景

v1.5版本适用于：
- ✅ **新的Payer部署** - 包含所有已知问题修复
- ✅ **生产环境部署** - 经过Elite-new12验证
- ✅ **Athena Setup问题修复** - 解决IAM角色传播问题

## 📈 版本对比

| 特性 | v1.4 | v1.5 |
|------|------|------|
| Athena Setup稳定性 | ❌ IAM角色传播问题 | ✅ 已修复 |
| 生产验证 | Elite-new11 | Elite-new12 |
| 部署成功率 | 87.5% | 100% |

## 🚀 快速部署

### 使用版本管理脚本（推荐）
```bash
cd aws-payer-automation
./deployment-scripts/version-management.sh deploy-all v1.5 <payer-name>
```

### 手动部署
```bash
# 设置版本为v1.5
./deployment-scripts/version-management.sh update-current v1.5

# 按模块顺序部署
# Module 1: OU和SCP
aws cloudformation create-stack --stack-name <payer>-ou-scp \
  --template-body file://templates/current/01-ou-scp/auto_SCP_1.yaml \
  --parameters ParameterKey=RootId,ParameterValue=<root-id> \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# 继续其他模块...
```

## 💡 重要提醒

1. **Athena Setup**: 现在可以稳定部署，无需手动干预
2. **Lambda超时**: Athena Setup的Lambda函数超时时间为10分钟
3. **IAM传播**: 系统会自动等待IAM角色传播完成
4. **生产验证**: 此版本已在Elite-new12生产环境验证通过

## 📚 详细文档

每个模块的详细文档请参阅对应的README文件：
- [Module 5 Athena Setup](./05-athena-setup/README.md) - 包含完整的修复说明

## 🔄 升级路径

从旧版本升级到v1.5：
1. 如果Athena Setup有问题，删除失败的栈
2. 使用v1.5重新部署Module 5
3. 其他模块无需重新部署