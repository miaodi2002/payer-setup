# Payer部署管理系统

## 目录结构
```
payer-deployments/
├── README.md                    # 此文件：系统说明
├── config/                      # 配置文件
│   ├── payer-registry.json      # Payer注册表
│   ├── deployment-config.json   # 部署配置模板
│   └── global-settings.json     # 全局设置
├── templates/                   # 部署模板
│   ├── deployment-plan.md       # 部署计划模板
│   ├── progress-report.md       # 进度报告模板
│   └── checklist.md            # 检查清单模板
├── scripts/                     # 自动化脚本
│   ├── deploy-payer.sh         # 单个Payer部署脚本
│   ├── monitor-deployment.sh   # 部署监控脚本
│   ├── generate-report.sh      # 报告生成脚本
│   └── cleanup-deployment.sh   # 清理脚本
├── logs/                       # 日志目录
│   └── {payer-id}/            # 按Payer ID组织
│       ├── {date}/            # 按日期组织
│       └── deployment.log     # 主要部署日志
└── reports/                    # 报告目录
    └── {payer-id}/            # 按Payer ID组织
        ├── deployment-plan.md  # 部署计划
        ├── progress-report.md  # 进度报告
        ├── issues.md          # 问题记录
        └── completion-summary.md # 完成总结
```

## 核心功能
1. **统一的Payer管理**: 记录所有Payer信息和状态
2. **标准化部署流程**: 使用模板确保一致性
3. **实时进度跟踪**: 自动化监控和报告生成
4. **问题追踪和解决**: 集中记录和解决方案
5. **历史记录和审计**: 完整的部署历史

## 详细使用方法

### 1. 配置新的Payer
编辑 `/config/payer-registry.json`：
```json
{
  "payers": {
    "payer-001": {
      "company": "Example Corp",
      "master_account_email": "admin@example.com",
      "deployment_status": "pending",
      "created_date": "2024-01-15T10:00:00Z"
    }
  }
}
```

### 2. 部署Payer
```bash
cd payer-deployments

# 完整部署
./scripts/deploy-payer.sh payer-001

# 模拟运行（测试）
./scripts/deploy-payer.sh payer-001 --dry-run

# 部署特定模块
./scripts/deploy-payer.sh payer-001 --module 05-athena-setup

# 查看帮助
./scripts/deploy-payer.sh --help
```

### 3. 监控部署进度
```bash
# 查看当前状态
./scripts/monitor-deployment.sh payer-001

# 实时监控日志
./scripts/monitor-deployment.sh payer-001 logs
```

### 4. 生成报告
```bash
# 生成Markdown报告
./scripts/generate-report.sh payer-001

# 生成HTML报告
./scripts/generate-report.sh payer-001 --format html

# 生成JSON报告
./scripts/generate-report.sh payer-001 --format json
```

### 5. 清理部署
```bash
# 交互式清理
./scripts/cleanup-deployment.sh payer-001

# 强制清理
./scripts/cleanup-deployment.sh payer-001 --force

# 仅清理日志文件
./scripts/cleanup-deployment.sh payer-001 --logs-only

# 仅清理CloudFormation栈
./scripts/cleanup-deployment.sh payer-001 --stacks-only

# 清理但保留最近7天的日志
./scripts/cleanup-deployment.sh payer-001 --keep-recent
```

## 快速开始指南
1. 注册新Payer: 更新 `config/payer-registry.json`
2. 创建部署计划: 使用模板生成具体计划
3. 执行部署: 运行 `scripts/deploy-payer.sh`
4. 监控进度: 使用 `scripts/monitor-deployment.sh`
5. 生成报告: 运行 `scripts/generate-report.sh`

## 估算信息
- **单个Payer部署时间**: 2-3小时
- **并行部署能力**: 建议最多3个
- **资源需求**: 中等（CloudFormation栈创建）
- **风险等级**: 低-中等（已测试的模板）