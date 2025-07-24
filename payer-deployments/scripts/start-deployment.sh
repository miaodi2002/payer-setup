#!/bin/bash

# Payer标准化部署启动脚本
# 使用方法: ./start-deployment.sh <payer-name>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_PATH="$(dirname "$SCRIPT_DIR")"
PAYER_NAME="${1:-Unknown-Payer}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "=========================================="
echo "🚀 Payer标准化部署启动向导"
echo "=========================================="
echo ""
log_info "Payer名称: $PAYER_NAME"
echo ""

# 查找最新的环境变量文件
LATEST_ENV_FILE=$(ls -t $DEPLOYMENT_PATH/config/production-variables-*.sh 2>/dev/null | head -1)

if [ -z "$LATEST_ENV_FILE" ]; then
    echo "❌ 未找到环境变量文件！"
    echo "请先运行: ./scripts/pre-deployment-check.sh"
    exit 1
fi

log_success "找到环境变量文件: $(basename $LATEST_ENV_FILE)"
echo ""

log_info "🔄 加载环境变量..."
source "$LATEST_ENV_FILE"
echo ""

log_info "📋 部署模块顺序:"
echo "   Module 1: OU和SCP设置 (可选)"
echo "   Module 2: BillingConductor和账户创建 ⭐️ 核心"
echo "   Module 3: Pro forma CUR设置"
echo "   Module 4: RISP CUR设置"
echo "   Module 5: Athena环境设置"
echo "   Module 6: 账户自动管理 (可选)"
echo "   Module 7: CloudFront监控 (可选)"
echo ""

log_info "📝 建议的部署命令序列:"
echo ""

# 生成具体的部署命令
echo "# ============ 开始部署 ============"
echo ""

# Module 1 (可选)
echo "# Module 1: OU和SCP设置 (可选，如果需要组织结构)"
echo "aws cloudformation create-stack \\"
echo "  --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-ou-scp-\${TIMESTAMP}\" \\"
echo "  --template-body file://\$PROJECT_PATH/templates/01-ou-scp/auto_SCP_1.yaml \\"
echo "  --capabilities CAPABILITY_NAMED_IAM \\"
echo "  --region \$REGION \\"
echo "  --tags Key=Module,Value=Module1 Key=Payer,Value=$PAYER_NAME"
echo ""

# Module 2 (核心)
echo "# Module 2: BillingConductor (核心模块，必须)"
echo "aws cloudformation create-stack \\"
echo "  --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-billing-conductor-\${TIMESTAMP}\" \\"
echo "  --template-body file://\$PROJECT_PATH/templates/02-billing-conductor/billing_conductor.yaml \\"
echo "  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\"
echo "  --region \$REGION \\"
echo "  --tags Key=Module,Value=Module2 Key=Payer,Value=$PAYER_NAME"
echo ""
echo "# ⚠️ 等待Module 2完成 (预计30-45分钟)"
echo "# aws cloudformation wait stack-create-complete --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-billing-conductor-\${TIMESTAMP}\""
echo ""

# Module 3 & 4 (可并行)
echo "# Module 3 & 4: CUR设置 (可并行执行)"
echo "aws cloudformation create-stack \\"
echo "  --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-cur-proforma-\${TIMESTAMP}\" \\"
echo "  --template-body file://\$PROJECT_PATH/templates/03-cur-proforma/cur_export_proforma.yaml \\"
echo "  --capabilities CAPABILITY_IAM \\"
echo "  --region \$REGION \\"
echo "  --tags Key=Module,Value=Module3 Key=Payer,Value=$PAYER_NAME &"
echo ""
echo "aws cloudformation create-stack \\"
echo "  --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-cur-risp-\${TIMESTAMP}\" \\"
echo "  --template-body file://\$PROJECT_PATH/templates/04-cur-risp/cur_export_risp.yaml \\"
echo "  --capabilities CAPABILITY_IAM \\"
echo "  --region \$REGION \\"
echo "  --tags Key=Module,Value=Module4 Key=Payer,Value=$PAYER_NAME &"
echo ""
echo "wait  # 等待Module 3和4完成"
echo ""

# Module 5
echo "# Module 5: Athena环境设置"
echo "aws cloudformation create-stack \\"
echo "  --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-athena-setup-\${TIMESTAMP}\" \\"
echo "  --template-body file://\$PROJECT_PATH/templates/05-athena-setup/athena_setup.yaml \\"
echo "  --capabilities CAPABILITY_IAM \\"
echo "  --region \$REGION \\"
echo "  --tags Key=Module,Value=Module5 Key=Payer,Value=$PAYER_NAME"
echo ""

# Module 6 & 7 (可选)
echo "# Module 6 & 7: 管理功能 (可选)"
echo "aws cloudformation create-stack \\"
echo "  --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-account-management-\${TIMESTAMP}\" \\"
echo "  --template-body file://\$PROJECT_PATH/templates/06-account-auto-management/account_auto_move_fixed.yaml \\"
echo "  --capabilities CAPABILITY_IAM \\"
echo "  --region \$REGION \\"
echo "  --tags Key=Module,Value=Module6 Key=Payer,Value=$PAYER_NAME &"
echo ""
echo "aws cloudformation create-stack \\"
echo "  --stack-name \"\${STACK_PREFIX}-\${PAYER_NAME}-cloudfront-monitoring-\${TIMESTAMP}\" \\"
echo "  --template-body file://\$PROJECT_PATH/templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml \\"
echo "  --capabilities CAPABILITY_IAM \\"
echo "  --region \$REGION \\"
echo "  --tags Key=Module,Value=Module7 Key=Payer,Value=$PAYER_NAME &"
echo ""
echo "wait  # 等待所有模块完成"
echo ""
echo "# ============ 部署完成 ============"

echo ""
log_info "💡 使用建议:"
log_info "1. 复制上述命令到终端逐个执行"
log_info "2. 每个模块完成后验证结果"
log_info "3. 核心模块(Module 2)必须等待完成再进行后续模块"
log_info "4. 详细指南请参考: PRODUCTION-DEPLOYMENT-GUIDE.md"
echo ""
log_success "环境变量已加载，可以开始部署！"
