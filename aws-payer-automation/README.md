# AWS Payer自动化初始化项目

## 项目概述

由于AWS 6月政策变更，不再允许RISP跨客户共享，需要为每个客户创建独立Payer。本项目提供基于CloudFormation + Lambda的模块化自动化方案，包含6个核心模块，实现AWS Reseller Payer账户的完全自动化初始化。

## 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Organizations                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Free OU   │  │  Block OU   │  │  Normal OU  │         │
│  │             │  │             │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                           │                                 │
│                    ┌─────────────┐                         │
│                    │ Master Acct │                         │
│                    └─────────────┘                         │
│                           │                                 │
│                    ┌─────────────┐                         │
│                    │  Bills Acct │ ←── BillingConductor    │
│                    └─────────────┘                         │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────────────────┐
                    │    CUR Exports      │
                    │ ┌─────────────────┐ │
                    │ │  Pro forma CUR  │ │ ← BillingGroup视图
                    │ └─────────────────┘ │
                    │ ┌─────────────────┐ │
                    │ │   RISP CUR      │ │ ← 标准定价
                    │ └─────────────────┘ │
                    └─────────────────────┘
```

## 模块说明

### Module 1: OU和SCP设置
- 创建Free、Block、Normal三个OU
- 部署7个SCP策略，包括防止预留实例、限制实例大小、禁用root用户等
- 自动将SCP附加到相应的OU

### Module 2: BillingConductor设置
- 创建新AWS账户（使用+bills邮箱别名）
- 创建BillingGroup用于pro forma定价
- 处理邮箱冲突（自动添加数字后缀）

### Module 3: Pro forma CUR Export
- 创建S3存储桶用于CUR数据
- 设置Legacy CUR导出（使用BillingGroup的pro forma定价）
- 配置Athena集成

### Module 4: RISP CUR Export
- 创建独立的S3存储桶
- 设置标准Legacy CUR导出（不使用pro forma定价）
- 提供标准AWS定价数据

### Module 5: Athena环境设置
- 创建统一的Glue Database管理CUR数据表
- 为Pro forma和RISP CUR分别创建Glue Crawler
- 设置Lambda函数处理自动化数据发现
- 配置S3事件通知自动触发数据更新
- 创建状态表跟踪CUR数据生成状态

### Module 6: 账户自动移动
- 监控AWS Organizations事件（CreateAccountResult、AcceptHandshake）
- 自动将新加入的账户移动到Normal OU
- 应用SCP限制防止购买预付费服务
- CloudTrail日志记录所有账户移动活动

## 快速开始

### 前置条件

1. **AWS CLI配置**
   ```bash
   aws configure
   ```

2. **必要权限**
   - Organizations管理员权限
   - IAM权限管理
   - S3存储桶创建
   - CloudFormation完整权限
   - BillingConductor权限
   - Glue和Athena权限

3. **启用服务**
   - AWS Organizations
   - SCP功能
   - BillingConductor（如需要）
   - AWS Glue（自动启用）

### 一键部署

```bash
# 克隆项目
git clone <repository-url>
cd aws-payer-automation

# 验证模板
./scripts/validate.sh

# 部署所有模块
./scripts/deploy.sh
```

### 分步部署

```bash
# 获取Root ID
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)

# 部署Module 1
./scripts/deploy-single.sh 1 --root-id $ROOT_ID

# 部署Module 2
./scripts/deploy-single.sh 2

# 获取BillingGroup ARN
BILLING_GROUP_ARN=$(aws cloudformation describe-stacks \
  --stack-name payer-billing-conductor-* \
  --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' \
  --output text)

# 部署Module 3
./scripts/deploy-single.sh 3 --billing-group-arn $BILLING_GROUP_ARN

# 部署Module 4
./scripts/deploy-single.sh 4

# 获取ProformaBucket等参数并部署Module 5
PROFORMA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-proforma-* \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

RISP_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-risp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPBucketName`].OutputValue' \
  --output text)

# 部署Module 5
./scripts/deploy-single.sh 5 --proforma-bucket $PROFORMA_BUCKET --risp-bucket $RISP_BUCKET --proforma-report $ACCOUNT_ID --risp-report risp-$ACCOUNT_ID

# 获取Normal OU ID并部署Module 6
NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name payer-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text)

# 部署Module 6
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID
```

## 项目结构

```
aws-payer-automation/
├── README.md                    # 项目总览（本文件）
├── templates/                   # CloudFormation模板
│   ├── 01-ou-scp/
│   │   ├── auto_SCP_1.yaml     # OU和SCP设置
│   │   └── README.md
│   ├── 02-billing-conductor/
│   │   ├── billing_conductor.yaml # BillingConductor设置
│   │   └── README.md
│   ├── 03-cur-proforma/
│   │   ├── cur_export_proforma.yaml # Pro forma CUR
│   │   └── README.md
│   ├── 04-cur-risp/
│   │   ├── cur_export_risp.yaml # RISP CUR
│   │   └── README.md
│   ├── 05-athena-setup/
│   │   ├── athena_setup.yaml    # Athena环境设置
│   │   └── README.md
│   └── 06-account-auto-management/
│       ├── account_auto_move.yaml # 账户自动移动
│       └── README.md
├── scripts/                     # 部署脚本
│   ├── deploy.sh               # 完整部署
│   ├── deploy-single.sh        # 单模块部署
│   ├── validate.sh             # 模板验证
│   └── cleanup.sh              # 清理脚本
├── config/
│   └── parameters-example.json # 参数配置示例
└── docs/                       # 详细文档
    ├── setup-guide.md
    ├── deployment-guide.md
    └── troubleshooting.md
```

## 部署时间

- **Module 1**: ~10分钟
- **Module 2**: ~30分钟（账户创建）
- **Module 3**: ~10分钟
- **Module 4**: ~10分钟
- **Module 5**: ~15分钟（Athena设置和初始爬取）
- **Module 6**: ~5分钟（账户自动移动设置）
- **总计**: ~80分钟

## 重要说明

⚠️ **注意事项**
- 账户创建可能需要30分钟
- CUR报告需要24小时生成首次数据
- 只能在us-east-1区域创建CUR
- 请确保邮箱地址唯一性
- Athena爬虫需要10-15分钟完成初始数据发现

🔒 **安全特性**
- IAM角色遵循最小权限原则
- S3存储桶启用版本控制和公共访问阻止
- 包含完整的错误处理和回滚机制

## 常用命令

```bash
# 验证所有模板
./scripts/validate.sh

# 查看已部署的栈
./scripts/cleanup.sh --list

# 删除特定栈
./scripts/cleanup.sh --delete-stack stack-name

# 查看部署状态
aws cloudformation describe-stacks --stack-name payer-*

# 获取BillingGroup ARN
aws cloudformation describe-stacks \
  --stack-name payer-billing-conductor-* \
  --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' \
  --output text

# 获取Athena数据库名称
aws cloudformation describe-stacks \
  --stack-name payer-athena-setup-* \
  --query 'Stacks[0].Outputs[?OutputKey==`DatabaseName`].OutputValue' \
  --output text

# 获取Normal OU ID
aws cloudformation describe-stacks \
  --stack-name payer-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text

# 检查账户自动移动状态
aws logs filter-log-events \
  --log-group-name /aws/lambda/AccountAutoMover \
  --start-time $(date -d '1 hour ago' +%s)000

# 查询Pro forma CUR数据示例
aws athena start-query-execution \
  --query-string "SELECT line_item_product_code, SUM(line_item_blended_cost) as total_cost FROM athenacurcfn_123456789012.123456789012 WHERE year='2024' AND month='01' GROUP BY line_item_product_code ORDER BY total_cost DESC LIMIT 10" \
  --result-configuration OutputLocation=s3://your-athena-results-bucket/

# 比较Pro forma和RISP定价
aws athena start-query-execution \
  --query-string "SELECT p.line_item_product_code, SUM(p.line_item_blended_cost) as proforma_cost, SUM(r.line_item_unblended_cost) as risp_cost FROM athenacurcfn_123456789012.123456789012 p JOIN athenacurcfn_123456789012.risp_123456789012 r ON p.line_item_product_code = r.line_item_product_code WHERE p.year='2024' AND p.month='01' GROUP BY p.line_item_product_code" \
  --result-configuration OutputLocation=s3://your-athena-results-bucket/
```

## 故障排除

### 常见问题

1. **邮箱已存在错误**
   - 系统会自动添加数字后缀解决冲突

2. **CUR创建失败**
   - 确认在us-east-1区域部署
   - 检查S3权限

3. **SCP附加失败**
   - 验证Organizations权限
   - 确认SCP功能已启用

4. **账户创建超时**
   - 等待最多30分钟
   - 检查AWS服务状态

### 日志查看

```bash
# CloudFormation事件
aws cloudformation describe-stack-events --stack-name <stack-name>

# Lambda日志
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/
```

## 支持与贡献

- 详细文档：`docs/`目录
- 问题报告：GitHub Issues
- 配置示例：`config/parameters-example.json`

## 许可证

本项目为内部使用，请遵守公司政策和AWS使用条款。