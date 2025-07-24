# AWS Payer Automation - 模组部署测试指南

## 测试目录结构

本目录包含7个模组的独立测试文档，用于逐个验证部署流程：

```
deployment-testing/
├── README.md                    # 本文件 - 测试总览
├── module-01-test.md           # 模组1: OU和SCP设置测试
├── module-02-test.md           # 模组2: BillingConductor测试
├── module-03-test.md           # 模组3: Pro forma CUR测试
├── module-04-test.md           # 模组4: RISP CUR测试
├── module-05-test.md           # 模组5: Athena环境测试
├── module-06-test.md           # 模组6: 账户自动移动测试
├── module-07-test.md           # 模组7: CloudFront监控测试
└── troubleshooting.md          # 故障排除指南
```

## 测试顺序和依赖关系

### 必须按顺序执行的模组
1. **模组1** → **模组2** → **模组3** (Pro forma CUR依赖BillingGroup)
2. **模组1** → **模组6** (账户自动移动依赖Normal OU)
3. **模组1** → **模组7** (CloudFront监控依赖Normal OU)

### 可以并行执行的模组
- **模组3** 和 **模组4** (两个CUR模组互相独立)
- **模组3 + 模组4** 完成后 → **模组5** (Athena依赖两个CUR)

### 推荐测试顺序
```
步骤1: 模组1 (OU和SCP)
步骤2: 模组2 (BillingConductor)
步骤3: 模组3 (Pro forma CUR) + 模组4 (RISP CUR) [可并行]
步骤4: 模组5 (Athena环境)
步骤5: 模组6 (账户自动移动)
步骤6: 模组7 (CloudFront监控)
```

## 前置条件检查

在开始任何模组测试之前，请确保：

### 1. AWS环境准备
```bash
# 检查AWS CLI配置
aws sts get-caller-identity

# 检查区域设置
aws configure get region
# 应该返回: us-east-1 (CUR导出必须在此区域)
```

### 2. 权限验证
```bash
# 检查Organizations权限
aws organizations describe-organization

# 检查IAM权限
aws iam get-account-summary

# 检查BillingConductor权限
aws billingconductor list-billing-groups --region us-east-1
```

### 3. 服务启用检查
```bash
# 检查Organizations中的SCP功能是否启用
aws organizations describe-organization | grep -i scp

# 获取Root ID（后续测试会用到）
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Root ID: $ROOT_ID"
```

## 测试流程说明

每个模组测试文档包含：

1. **模组概述** - 模组功能和目标
2. **前置条件** - 该模组特定的依赖和要求
3. **部署步骤** - 详细的部署命令和参数
4. **验证检查** - 部署成功的验证方法
5. **故障排除** - 常见问题和解决方案
6. **清理步骤** - 如何清理该模组资源

## 全局变量设置

在开始测试前，设置这些变量（会在多个模组中使用）：

```bash
# 基础变量
export TIMESTAMP=$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"

# Organizations相关
export ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
export MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)

# 项目路径
export PROJECT_PATH="/Users/di.miao/Work/payer-setup/aws-payer-automation"
export TEST_PATH="/Users/di.miao/Work/payer-setup/deployment-testing"

echo "=== 全局变量设置完成 ==="
echo "ROOT_ID: $ROOT_ID"
echo "MASTER_ACCOUNT_ID: $MASTER_ACCOUNT_ID"
echo "TIMESTAMP: $TIMESTAMP"
```

## 测试日志记录

建议为每个模组测试创建日志文件：

```bash
# 创建日志目录
mkdir -p $TEST_PATH/logs

# 示例：模组1测试日志
LOG_FILE="$TEST_PATH/logs/module-01-$(date +%Y%m%d_%H%M%S).log"
```

## 测试状态追踪

在每个模组测试文档中，你会看到状态检查表：

- ✅ **已完成** - 测试通过
- ❌ **失败** - 需要修复
- ⏳ **进行中** - 正在执行
- ⏸️ **暂停** - 等待依赖或手动干预

## 重要提醒

1. **成本考虑**: 某些资源可能产生费用，特别是S3存储和Lambda执行
2. **时间要求**: 某些操作（如账户创建）可能需要30分钟
3. **数据保护**: 在清理资源前确保重要数据已备份
4. **依赖管理**: 删除资源时注意依赖顺序，通常与部署顺序相反

## 联系支持

如果在测试过程中遇到问题：
1. 查看对应模组的故障排除部分
2. 检查 `troubleshooting.md` 文档
3. 查看CloudFormation事件日志获取详细错误信息

---

**开始测试**: 请从 `module-01-test.md` 开始您的测试流程。