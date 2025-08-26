# AWS Payer自动化初始化项目

## 项目概述

由于AWS 6月政策变更，不再允许RISP跨客户共享，需要为每个客户创建独立Payer。本项目提供基于CloudFormation + Lambda的模块化自动化方案，包含7个核心模块，实现AWS Reseller Payer账户的完全自动化初始化。

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
- ⚠️ **重要**: 使用v1.5修复版 `athena_setup_fixed.yaml`
- ⚠️ **关键参数**: `ProformaReportName`必须使用主账户ID(如534877455433)，**不要**使用"proforma-534877455433"

### Module 6: 账户自动移动
- 监控AWS Organizations事件（CreateAccountResult、AcceptHandshake）
- 自动将新加入的账户移动到Normal OU
- 应用SCP限制防止购买预付费服务
- CloudTrail日志记录所有账户移动活动

### Module 7: CloudFront跨账户监控
- 智能OAM (Observability Access Manager)基础设施设置
- 跨账户CloudFront流量集中监控
- 100MB阈值告警（可配置）
- Telegram Bot实时通知具体超量账户

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
   - EventBridge权限（Module 6需要）
   - CloudTrail权限（Module 6需要）

3. **启用服务**
   - AWS Organizations
   - SCP功能
   - BillingConductor（如需要）
   - AWS Glue（自动启用）

### IAM用户权限策略

部署用户需要以下IAM策略权限：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "organizations:*",
                "billingconductor:*",
                "cur:*",
                "s3:*",
                "lambda:*",
                "glue:*",
                "cloudformation:*",
                "logs:*",
                "kms:*",
                "cloudtrail:*",
                "events:*",
                "athena:*",
                "oam:*",
                "sns:*",
                "cloudwatch:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:GetRole",
                "iam:UpdateRole",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:GetRolePolicy",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:ListRolePolicies",
                "iam:ListAttachedRolePolicies",
                "iam:PassRole",
                "iam:TagRole",
                "iam:UntagRole",
                "iam:ListRoles"
            ],
            "Resource": "*"
        }
    ]
}
```

**新增权限说明**：
- `events:*`: Module 6需要创建和管理EventBridge规则
- `athena:*`: Module 5需要创建Athena工作组和查询权限
- `oam:*`: Module 7需要创建和管理OAM Sink和Link

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

# 部署Module 5（使用简化版模板）
./scripts/deploy-single.sh 5 --proforma-bucket $PROFORMA_BUCKET --risp-bucket $RISP_BUCKET --proforma-report $ACCOUNT_ID --risp-report risp-$ACCOUNT_ID

# 获取Normal OU ID并部署Module 6
NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name payer-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text)

# 部署Module 6
./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID

# 获取Master Account名称并部署Module 7 (CloudFront监控)
MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
PAYER_NAME=$(aws organizations describe-account --account-id $MASTER_ACCOUNT_ID --query 'Account.Name' --output text)
./scripts/deploy-single.sh 7 --payer-name "$PAYER_NAME"
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
│   │   ├── athena_setup.yaml    # Athena环境设置（原版，有语法问题）
│   │   ├── athena_setup_simplified.yaml # 简化版（推荐使用）
│   │   └── README.md
│   ├── 06-account-auto-management/
│   │   ├── account_auto_move.yaml # 账户自动移动
│   │   └── README.md
│   └── 07-cloudfront-monitoring/
│       ├── cloudfront_monitoring.yaml # CloudFront监控
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
- **Module 7**: ~10分钟（OAM设置和CloudFront监控）
- **总计**: ~90分钟

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

# 检查CloudFront监控状态（Module 7）
aws oam list-sinks
aws cloudwatch describe-alarms --alarm-names "*CloudFront*"

# 查看CloudFront告警日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/${PAYER_NAME}-CloudFront-Alert \
  --start-time $(date -d '24 hours ago' +%s)000

# 检查OAM设置状态
aws logs filter-log-events \
  --log-group-name /aws/lambda/${PAYER_NAME}-OAM-Setup \
  --start-time $(date -d '1 hour ago' +%s)000
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

5. **EventBridge权限错误**
   - 错误信息：`is not authorized to perform: events:DescribeRule`
   - 解决方案：为setup_user添加`events:*`权限
   - 参考上面的完整IAM策略

6. **Module 5 Lambda内联代码语法错误**
   - 错误信息：`Runtime.UserCodeSyntaxError`
   - 原因：`athena_setup.yaml`中Lambda内联代码语法错误
   - 解决方案：使用v1.5版本`athena_setup_fixed.yaml`模板

7. **Module 5 Athena无数据问题** ⚠️ **新发现**
   - 问题：Glue Crawler创建成功但Athena查询无数据
   - 根因：Pro forma Crawler S3路径配置错误
   - 错误配置：`s3://bucket/daily/proforma-ACCOUNTID/`
   - 正确配置：`s3://bucket/daily/ACCOUNTID/` (使用主账户ID)
   - 解决方案：v1.5版本已修复路径配置和参数验证

8. **Module 6账户移动失败**
   - 问题1：JSON键大小写错误（`Type`应为`type`，`Id`应为`id`）
   - 问题2：AcceptHandshake事件中使用错误的master账户ID字段
   - 解决方案：使用`recipientAccountId`而非`userIdentity.accountId`
   - 状态：✅ 已在`account_auto_move_fixed.yaml`中修复

9. **Module 6部署失败**
   - 确认CloudTrail S3存储桶策略正确
   - 检查EventBridge规则创建权限
   - 验证Lambda函数权限

10. **Module 7 StackSet部署失败**
   - 错误信息：缺少`AWSCloudFormationStackSetAdministrationRole`
   - 解决方案：创建必要的StackSet IAM角色或使用SERVICE_MANAGED权限模型
   - 状态：⚠️ 核心监控功能已部署（80%完成），StackSet集成待完善

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