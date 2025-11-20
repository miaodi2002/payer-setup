#!/bin/bash

# Payer部署前环境检查脚本
# 基于测试指南的前置条件要求

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_PATH="$(dirname "$SCRIPT_DIR")"

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "🔍 Payer部署前环境检查"
echo "=========================================="

# 检查结果变量
CHECK_PASSED=true

log_info "步骤1: 检查AWS CLI配置"
if aws sts get-caller-identity >/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    log_success "AWS凭证配置正确"
    log_info "账户ID: $ACCOUNT_ID"
    log_info "用户: $USER_ARN"
else
    log_error "AWS凭证配置失败，请检查aws configure"
    CHECK_PASSED=false
fi

log_info "步骤2: 检查区域设置"
REGION=$(aws configure get region)
if [ "$REGION" = "us-east-1" ]; then
    log_success "区域设置正确: $REGION"
else
    log_error "区域必须设置为us-east-1，当前: $REGION"
    log_info "修复方法: aws configure set region us-east-1"
    CHECK_PASSED=false
fi

log_info "步骤3: 检查/创建Organizations"
if aws organizations describe-organization >/dev/null 2>&1; then
    ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)
    MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
    log_success "Organizations已存在"
    log_info "Organization ID: $ORG_ID"
    log_info "Master Account: $MASTER_ACCOUNT_ID"
    
    if [ "$ACCOUNT_ID" = "$MASTER_ACCOUNT_ID" ]; then
        log_success "当前账户是Organizations的Master Account ✅"
    else
        log_success "当前账户可以访问Organizations ✅"
        log_info "当前账户: $ACCOUNT_ID"
        log_info "Master账户: $MASTER_ACCOUNT_ID"
    fi
else
    log_warning "Organizations不存在，正在创建..."
    log_info "创建Organizations，当前账户将成为Master Account"
    
    if aws organizations create-organization --feature-set ALL >/dev/null 2>&1; then
        log_success "Organizations创建成功! 🎉"
        
        # 等待几秒让Organizations完全初始化
        sleep 5
        
        # 获取新创建的Organizations信息
        ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)
        MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
        
        log_success "Organization ID: $ORG_ID"
        log_success "Master Account: $MASTER_ACCOUNT_ID (当前账户)"
        log_info "✅ 当前账户现在是Organizations的Master Account"
    else
        log_error "Organizations创建失败!"
        log_error "可能原因:"
        log_error "1. 账户权限不足"
        log_error "2. 账户已经是其他Organization的成员"
        log_error "3. 账户类型不支持创建Organizations"
        CHECK_PASSED=false
    fi
fi

log_info "步骤4: 检查BillingConductor权限"
if aws billingconductor list-billing-groups --region us-east-1 >/dev/null 2>&1; then
    BILLING_GROUPS=$(aws billingconductor list-billing-groups --region us-east-1 --query 'BillingGroups | length(@)' --output text)
    log_success "BillingConductor权限验证通过"
    log_info "现有BillingGroups数量: $BILLING_GROUPS"
else
    log_error "BillingConductor权限检查失败!"
    log_error "错误: 账户不是Payer账户或BillingConductor未启用"
    log_error "❌ 无法部署BillingConductor模块"
    echo ""
    log_info "可能的解决方案:"
    log_info "1. 确认账户是AWS Payer账户"
    log_info "2. 联系AWS开启BillingConductor服务"
    log_info "3. 切换到具有BillingConductor权限的账户"
    CHECK_PASSED=false
fi

log_info "步骤5: 检查IAM权限"
if aws iam get-account-summary >/dev/null 2>&1; then
    log_success "IAM权限验证通过"
else
    log_error "IAM权限不足，需要管理员级别权限"
    CHECK_PASSED=false
fi

log_info "步骤6: 检查必要的模板文件"
PROJECT_PATH="/Users/di.miao/Work/BIP/payer-setup/aws-payer-automation"
REQUIRED_TEMPLATES=(
    "02-billing-conductor/billing_conductor.yaml"
    "03-cur-proforma/cur_export_proforma.yaml"
    "04-cur-risp/cur_export_risp.yaml"
    "05-athena-setup/athena_setup.yaml"
)

for template in "${REQUIRED_TEMPLATES[@]}"; do
    if [ -f "$PROJECT_PATH/templates/$template" ]; then
        log_success "模板存在: $template"
    else
        log_error "缺少必要模板: $template"
        CHECK_PASSED=false
    fi
done

# 可选模板检查
OPTIONAL_TEMPLATES=(
    "01-ou-scp/auto_SCP_1.yaml"
    "06-account-auto-management/account_auto_move_fixed.yaml"
    "07-cloudfront-monitoring/cloudfront_monitoring.yaml"
)

for template in "${OPTIONAL_TEMPLATES[@]}"; do
    if [ -f "$PROJECT_PATH/templates/$template" ]; then
        log_success "可选模板存在: $template"
    else
        log_warning "可选模板不存在: $template (将跳过该模块)"
    fi
done

echo ""
echo "=========================================="
echo "🎯 检查结果汇总"
echo "=========================================="

if [ "$CHECK_PASSED" = true ]; then
    log_success "✅ 所有关键检查通过！"
    log_success "✅ 环境已准备就绪，可以开始部署"
    echo ""
    
    # 生成环境变量
    log_info "步骤7: 生成环境变量文件"
    ENV_FILE="$DEPLOYMENT_PATH/config/production-variables-$(date +%Y%m%d_%H%M%S).sh"
    mkdir -p "$(dirname "$ENV_FILE")"
    
    cat > "$ENV_FILE" << EOF
#!/bin/bash
# 生产部署环境变量 - $(date)
# 由pre-deployment-check.sh自动生成

# 基础环境
export TIMESTAMP=\$(date +%s)
export REGION="us-east-1"
export STACK_PREFIX="payer"

# AWS环境信息
export CURRENT_ACCOUNT_ID="$ACCOUNT_ID"
export ORGANIZATION_ID="$ORG_ID"
export MASTER_ACCOUNT_ID="$MASTER_ACCOUNT_ID"

# 项目路径
export PROJECT_PATH="/Users/di.miao/Work/BIP/payer-setup/aws-payer-automation"
export DEPLOYMENT_PATH="/Users/di.miao/Work/BIP/payer-setup/payer-deployments"

# Organizations结构 (需要时可用)
export ROOT_ID=\$(aws organizations list-roots --query 'Roots[0].Id' --output text 2>/dev/null || echo "")

echo "✅ 生产环境变量已加载"
echo "当前账户: \$CURRENT_ACCOUNT_ID"
echo "Organization: \$ORGANIZATION_ID"
echo "Master账户: \$MASTER_ACCOUNT_ID"
echo "时间戳: \$TIMESTAMP"
EOF
    
    chmod +x "$ENV_FILE"
    log_success "环境变量文件已创建: $ENV_FILE"
    
    echo ""
    echo "=========================================="
    echo "🚀 准备开始标准化部署流程"
    echo "=========================================="
    echo ""
    log_success "✅ 推荐使用标准化手动部署流程 (选项1)"
    echo ""
    log_info "📋 标准化部署步骤:"
    log_info "1. 加载环境变量: source $ENV_FILE"
    log_info "2. 开始模块化部署: 按照PRODUCTION-DEPLOYMENT-GUIDE.md的顺序"
    log_info "3. 每个模块部署后进行验证"
    echo ""
    
    # 创建快速启动脚本
    STARTER_SCRIPT="$DEPLOYMENT_PATH/scripts/start-deployment.sh"
    cat > "$STARTER_SCRIPT" << 'EOF'
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
EOF
    
    chmod +x "$STARTER_SCRIPT"
    
    log_info "🎯 已创建部署启动脚本: $STARTER_SCRIPT"
    echo ""
    log_info "🚀 快速开始部署:"
    log_success "   ./scripts/start-deployment.sh Elite-new11"
    echo ""
    log_info "或者手动执行:"
    log_info "   source $ENV_FILE"
    log_info "   # 然后按照PRODUCTION-DEPLOYMENT-GUIDE.md进行部署"
    echo ""
    
    exit 0
else
    log_error "❌ 关键检查失败！"
    log_error "❌ 环境未准备就绪，无法进行部署"
    echo ""
    log_info "请解决上述错误后重新运行此检查脚本"
    exit 1
fi