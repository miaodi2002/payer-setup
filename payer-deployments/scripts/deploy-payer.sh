#!/bin/bash

# Payer部署自动化脚本
# 使用方法: ./deploy-payer.sh <payer-id> [--dry-run]

set -e

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYER_DEPLOYMENTS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$PAYER_DEPLOYMENTS_DIR")"
AUTOMATION_DIR="$PROJECT_DIR/aws-payer-automation"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 帮助信息
show_help() {
    cat << EOF
Payer部署自动化脚本

使用方法:
    $0 <payer-id> [选项]

参数:
    payer-id        要部署的Payer ID (在payer-registry.json中定义)

选项:
    --dry-run       模拟运行，不执行实际部署
    --module        只部署指定模块 (例如: --module 02-billing-conductor)
    --skip-deps     跳过依赖检查
    --help          显示此帮助信息

示例:
    $0 payer-001                    # 完整部署payer-001
    $0 payer-002 --dry-run          # 模拟部署payer-002
    $0 payer-001 --module 05-athena-setup  # 只部署Athena模块

EOF
}

# 检查参数
if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

PAYER_ID="$1"
DRY_RUN=false
SPECIFIC_MODULE=""
SKIP_DEPS=false

# 解析参数
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --module)
            SPECIFIC_MODULE="$2"
            shift 2
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 创建日志目录
LOG_DIR="$PAYER_DEPLOYMENTS_DIR/logs/$PAYER_ID/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deployment.log"

# 创建报告目录
REPORT_DIR="$PAYER_DEPLOYMENTS_DIR/reports/$PAYER_ID"
mkdir -p "$REPORT_DIR"

# 开始部署
{
    log_info "开始部署 Payer: $PAYER_ID"
    log_info "日志文件: $LOG_FILE"
    log_info "模拟运行: $DRY_RUN"
    
    if [ -n "$SPECIFIC_MODULE" ]; then
        log_info "指定模块: $SPECIFIC_MODULE"
    fi

    # 验证Payer ID
    if ! jq -e ".payers[\"$PAYER_ID\"]" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json" > /dev/null; then
        log_error "Payer ID '$PAYER_ID' 在注册表中不存在"
        exit 1
    fi

    # 获取Payer信息
    PAYER_INFO=$(jq -r ".payers[\"$PAYER_ID\"]" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json")
    COMPANY_NAME=$(echo "$PAYER_INFO" | jq -r ".company")
    CONTACT_EMAIL=$(echo "$PAYER_INFO" | jq -r ".master_account_email")
    
    log_info "公司名称: $COMPANY_NAME"
    log_info "联系邮箱: $CONTACT_EMAIL"

    # 部署模块顺序
    MODULES=(
        "01-ou-scp"
        "02-billing-conductor"
        "03-cur-proforma"
        "04-cur-risp"
        "05-athena-setup"
        "06-account-auto-management"
        "07-cloudfront-monitoring"
    )

    # 如果指定了特定模块，只部署该模块
    if [ -n "$SPECIFIC_MODULE" ]; then
        MODULES=("$SPECIFIC_MODULE")
    fi

    # 部署开始时间
    DEPLOYMENT_START=$(date +%s)
    
    # 创建进度报告
    cp "$PAYER_DEPLOYMENTS_DIR/templates/progress-report.md" "$REPORT_DIR/progress-report.md"
    
    # 更新进度报告基本信息
    sed -i.bak "s/{payer-id}/$PAYER_ID/g" "$REPORT_DIR/progress-report.md"
    sed -i.bak "s/{start-time}/$(date)/g" "$REPORT_DIR/progress-report.md"
    sed -i.bak "s/{current-status}/部署中/g" "$REPORT_DIR/progress-report.md"

    # 部署各模块
    for MODULE in "${MODULES[@]}"; do
        log_info "开始部署模块: $MODULE"
        MODULE_START=$(date +%s)
        
        if [ "$DRY_RUN" = true ]; then
            log_info "[模拟] 部署模块 $MODULE"
            sleep 2  # 模拟部署时间
            log_success "[模拟] 模块 $MODULE 部署完成"
        else
            # 实际部署逻辑
            case $MODULE in
                "01-ou-scp")
                    log_info "部署OU和SCP设置..."
                    if [ -f "$AUTOMATION_DIR/templates/01-ou-scp/ou_scp.yaml" ]; then
                        aws cloudformation deploy \
                            --template-file "$AUTOMATION_DIR/templates/01-ou-scp/ou_scp.yaml" \
                            --stack-name "payer-$PAYER_ID-ou-scp" \
                            --capabilities CAPABILITY_IAM \
                            --region us-east-1 \
                            --parameter-overrides PayerId="$PAYER_ID" CompanyName="$COMPANY_NAME"
                    else
                        log_warning "OU/SCP模板不存在，跳过"
                    fi
                    ;;
                "02-billing-conductor")
                    log_info "部署BillingConductor..."
                    if [ -f "$AUTOMATION_DIR/templates/02-billing-conductor/billing_conductor.yaml" ]; then
                        aws cloudformation deploy \
                            --template-file "$AUTOMATION_DIR/templates/02-billing-conductor/billing_conductor.yaml" \
                            --stack-name "payer-$PAYER_ID-billing-conductor" \
                            --capabilities CAPABILITY_IAM \
                            --region us-east-1 \
                            --parameter-overrides \
                                PayerId="$PAYER_ID" \
                                CompanyName="$COMPANY_NAME" \
                                ContactEmail="$CONTACT_EMAIL"
                    else
                        log_error "BillingConductor模板不存在"
                        exit 1
                    fi
                    ;;
                "03-cur-proforma")
                    log_info "部署Pro forma CUR..."
                    if [ -f "$AUTOMATION_DIR/templates/03-cur-proforma/cur_proforma.yaml" ]; then
                        aws cloudformation deploy \
                            --template-file "$AUTOMATION_DIR/templates/03-cur-proforma/cur_proforma.yaml" \
                            --stack-name "payer-$PAYER_ID-cur-proforma" \
                            --capabilities CAPABILITY_IAM \
                            --region us-east-1 \
                            --parameter-overrides PayerId="$PAYER_ID"
                    else
                        log_warning "Pro forma CUR模板不存在，跳过"
                    fi
                    ;;
                "04-cur-risp") 
                    log_info "部署RISP CUR..."
                    if [ -f "$AUTOMATION_DIR/templates/04-cur-risp/cur_risp.yaml" ]; then
                        aws cloudformation deploy \
                            --template-file "$AUTOMATION_DIR/templates/04-cur-risp/cur_risp.yaml" \
                            --stack-name "payer-$PAYER_ID-cur-risp" \
                            --capabilities CAPABILITY_IAM \
                            --region us-east-1 \
                            --parameter-overrides PayerId="$PAYER_ID"
                    else
                        log_warning "RISP CUR模板不存在，跳过"
                    fi
                    ;;
                "05-athena-setup")
                    log_info "部署Athena环境..."
                    if [ -f "$AUTOMATION_DIR/templates/05-athena-setup/athena_setup.yaml" ]; then
                        # 获取新账户ID（从BillingConductor栈输出）
                        NEW_ACCOUNT_ID=$(aws cloudformation describe-stacks \
                            --stack-name "payer-$PAYER_ID-billing-conductor" \
                            --region us-east-1 \
                            --query "Stacks[0].Outputs[?OutputKey=='NewAccountId'].OutputValue" \
                            --output text 2>/dev/null || echo "")
                        
                        if [ -n "$NEW_ACCOUNT_ID" ]; then
                            aws cloudformation deploy \
                                --template-file "$AUTOMATION_DIR/templates/05-athena-setup/athena_setup.yaml" \
                                --stack-name "payer-$PAYER_ID-athena-setup" \
                                --capabilities CAPABILITY_IAM \
                                --region us-east-1 \
                                --parameter-overrides \
                                    PayerId="$PAYER_ID" \
                                    NewAccountId="$NEW_ACCOUNT_ID"
                            log_info "使用账户ID: $NEW_ACCOUNT_ID"
                        else
                            log_error "无法获取新账户ID，跳过Athena设置"
                        fi
                    else
                        log_error "Athena设置模板不存在"
                        exit 1
                    fi
                    ;;
                "06-account-auto-management")
                    log_info "部署账户自动管理..."
                    if [ -f "$AUTOMATION_DIR/templates/06-account-auto-management/account_management.yaml" ]; then
                        aws cloudformation deploy \
                            --template-file "$AUTOMATION_DIR/templates/06-account-auto-management/account_management.yaml" \
                            --stack-name "payer-$PAYER_ID-account-management" \
                            --capabilities CAPABILITY_IAM \
                            --region us-east-1 \
                            --parameter-overrides PayerId="$PAYER_ID"
                    else
                        log_warning "账户自动管理模板不存在，跳过"
                    fi
                    ;;
                "07-cloudfront-monitoring")
                    log_info "部署CloudFront监控..."
                    if [ -f "$AUTOMATION_DIR/templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml" ]; then
                        aws cloudformation deploy \
                            --template-file "$AUTOMATION_DIR/templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml" \
                            --stack-name "payer-$PAYER_ID-cloudfront-monitoring" \
                            --capabilities CAPABILITY_IAM \
                            --region us-east-1 \
                            --parameter-overrides PayerId="$PAYER_ID"
                    else
                        log_warning "CloudFront监控模板不存在，跳过"
                    fi
                    ;;
            esac
        fi
        
        MODULE_END=$(date +%s)
        MODULE_DURATION=$((MODULE_END - MODULE_START))
        log_success "模块 $MODULE 部署完成，用时: ${MODULE_DURATION}秒"
    done

    DEPLOYMENT_END=$(date +%s)
    TOTAL_DURATION=$((DEPLOYMENT_END - DEPLOYMENT_START))
    
    log_success "Payer $PAYER_ID 部署完成！"
    log_success "总用时: ${TOTAL_DURATION}秒 ($(($TOTAL_DURATION / 60))分钟)"

} 2>&1 | tee "$LOG_FILE"

echo "部署日志已保存至: $LOG_FILE"
echo "进度报告位置: $REPORT_DIR/progress-report.md"