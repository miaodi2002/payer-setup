#!/bin/bash

# 部署清理脚本
# 使用方法: ./cleanup-deployment.sh <payer-id> [--force] [--logs-only] [--stacks-only]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYER_DEPLOYMENTS_DIR="$(dirname "$SCRIPT_DIR")"
PAYER_ID="$1"
FORCE=false
LOGS_ONLY=false
STACKS_ONLY=false

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

show_help() {
    cat << EOF
部署清理脚本

使用方法:
    $0 <payer-id> [选项]

参数:
    payer-id        要清理的Payer ID

选项:
    --force         强制清理，不提示确认
    --logs-only     仅清理日志文件
    --stacks-only   仅清理CloudFormation栈
    --dry-run       模拟运行，不执行实际清理
    --keep-recent   保留最近7天的日志
    --help          显示此帮助信息

示例:
    $0 payer-001                    # 交互式清理payer-001
    $0 payer-002 --force            # 强制清理payer-002
    $0 payer-001 --logs-only        # 仅清理日志文件
    $0 payer-001 --stacks-only      # 仅清理CloudFormation栈
    $0 payer-001 --keep-recent      # 清理但保留最近7天的日志

EOF
}

# 检查参数
if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

DRY_RUN=false
KEEP_RECENT=false

# 解析参数
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --logs-only)
            LOGS_ONLY=true
            shift
            ;;
        --stacks-only)
            STACKS_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-recent)
            KEEP_RECENT=true
            shift
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 验证Payer ID
if ! jq -e ".payers[\"$PAYER_ID\"]" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json" > /dev/null 2>&1; then
    log_error "Payer ID '$PAYER_ID' 在注册表中不存在"
    exit 1
fi

LOG_DIR="$PAYER_DEPLOYMENTS_DIR/logs/$PAYER_ID"
REPORT_DIR="$PAYER_DEPLOYMENTS_DIR/reports/$PAYER_ID"

log_info "开始清理 Payer: $PAYER_ID"

# 获取Payer信息
PAYER_INFO=$(jq -r ".payers[\"$PAYER_ID\"]" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json")
COMPANY_NAME=$(echo "$PAYER_INFO" | jq -r ".company")

log_info "公司名称: $COMPANY_NAME"
if [ "$DRY_RUN" = true ]; then
    log_info "模拟运行模式，不会执行实际清理"
fi

# 确认清理操作
confirm_cleanup() {
    if [ "$FORCE" = false ]; then
        echo ""
        log_warning "即将清理以下内容:"
        
        if [ "$STACKS_ONLY" = false ]; then
            if [ -d "$LOG_DIR" ]; then
                local log_count=$(find "$LOG_DIR" -type f -name "*.log" | wc -l)
                echo "  - 日志文件: $log_count 个"
            fi
            
            if [ -d "$REPORT_DIR" ]; then
                local report_count=$(find "$REPORT_DIR" -type f | wc -l)
                echo "  - 报告文件: $report_count 个"
            fi
        fi
        
        if [ "$LOGS_ONLY" = false ]; then
            local stack_count=$(aws cloudformation list-stacks --region us-east-1 \
                --query "StackSummaries[?contains(StackName, 'payer') && StackStatus != 'DELETE_COMPLETE'].StackName" \
                --output text 2>/dev/null | wc -w)
            echo "  - CloudFormation栈: $stack_count 个"
        fi
        
        echo ""
        read -p "确认继续清理？[y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "清理操作已取消"
            exit 0
        fi
    fi
}

# 清理日志文件
cleanup_logs() {
    log_info "开始清理日志文件..."
    
    if [ ! -d "$LOG_DIR" ]; then
        log_info "日志目录不存在，跳过"
        return
    fi
    
    local files_cleaned=0
    
    if [ "$KEEP_RECENT" = true ]; then
        # 保留最近7天的日志
        local cutoff_date=$(date -d '7 days ago' +%Y%m%d)
        log_info "保留 $cutoff_date 之后的日志文件"
        
        while IFS= read -r -d '' file; do
            local file_date=$(basename "$(dirname "$file")" | cut -d'_' -f1)
            if [[ "$file_date" < "$cutoff_date" ]]; then
                if [ "$DRY_RUN" = true ]; then
                    log_info "[模拟] 删除旧日志: $file"
                else
                    rm -f "$file"
                    log_info "删除旧日志: $file"
                fi
                ((files_cleaned++))
            fi
        done < <(find "$LOG_DIR" -name "*.log" -type f -print0)
    else
        # 清理所有日志
        while IFS= read -r -d '' file; do
            if [ "$DRY_RUN" = true ]; then
                log_info "[模拟] 删除日志: $file"
            else
                rm -f "$file"
            fi
            ((files_cleaned++))
        done < <(find "$LOG_DIR" -name "*.log" -type f -print0)
        
        # 删除空目录
        if [ "$DRY_RUN" = false ]; then
            find "$LOG_DIR" -type d -empty -delete 2>/dev/null || true
        fi
    fi
    
    log_success "日志清理完成，处理了 $files_cleaned 个文件"
}

# 清理报告文件
cleanup_reports() {
    log_info "开始清理报告文件..."
    
    if [ ! -d "$REPORT_DIR" ]; then
        log_info "报告目录不存在，跳过"
        return
    fi
    
    local files_cleaned=0
    
    # 保留最新的progress-report.md，清理其他文件
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        if [[ "$filename" != "progress-report.md" ]]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[模拟] 删除报告: $file"
            else
                rm -f "$file"
                log_info "删除报告: $file"
            fi
            ((files_cleaned++))
        fi
    done < <(find "$REPORT_DIR" -type f -print0)
    
    log_success "报告清理完成，处理了 $files_cleaned 个文件"
}

# 清理CloudFormation栈
cleanup_stacks() {
    log_info "开始清理CloudFormation栈..."
    
    # 获取相关的CloudFormation栈
    local stacks=$(aws cloudformation list-stacks --region us-east-1 \
        --query "StackSummaries[?contains(StackName, 'payer') && StackStatus != 'DELETE_COMPLETE'].StackName" \
        --output text 2>/dev/null)
    
    if [ -z "$stacks" ]; then
        log_info "未找到相关的CloudFormation栈"
        return
    fi
    
    local stacks_cleaned=0
    
    for stack in $stacks; do
        log_info "处理栈: $stack"
        
        # 获取栈状态
        local stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$stack" \
            --region us-east-1 \
            --query "Stacks[0].StackStatus" \
            --output text 2>/dev/null)
        
        if [ "$stack_status" = "DELETE_IN_PROGRESS" ]; then
            log_info "栈 $stack 正在删除中，跳过"
            continue
        fi
        
        if [ "$DRY_RUN" = true ]; then
            log_info "[模拟] 删除栈: $stack (状态: $stack_status)"
        else
            log_info "删除栈: $stack (状态: $stack_status)"
            
            # 尝试删除栈
            if aws cloudformation delete-stack --stack-name "$stack" --region us-east-1; then
                log_success "栈删除请求已提交: $stack"
                
                # 等待删除完成（可选）
                log_info "等待栈删除完成: $stack"
                aws cloudformation wait stack-delete-complete --stack-name "$stack" --region us-east-1 &
            else
                log_error "删除栈失败: $stack"
            fi
        fi
        
        ((stacks_cleaned++))
    done
    
    log_success "CloudFormation栈清理完成，处理了 $stacks_cleaned 个栈"
}

# 更新注册表状态
update_registry_status() {
    if [ "$DRY_RUN" = false ]; then
        log_info "更新注册表状态..."
        
        # 更新部署状态为已清理
        local temp_file=$(mktemp)
        jq ".payers[\"$PAYER_ID\"].deployment_status = \"cleaned\" | 
            .payers[\"$PAYER_ID\"].last_cleanup = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" \
            "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json" > "$temp_file"
        
        mv "$temp_file" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json"
        log_success "注册表状态已更新"
    fi
}

# 执行清理
confirm_cleanup

if [ "$STACKS_ONLY" = false ]; then
    cleanup_logs
    cleanup_reports
fi

if [ "$LOGS_ONLY" = false ]; then
    cleanup_stacks
fi

update_registry_status

log_success "Payer $PAYER_ID 清理完成！"

# 显示清理后的状态
echo ""
log_info "清理后状态:"
if [ -d "$LOG_DIR" ]; then
    local remaining_logs=$(find "$LOG_DIR" -name "*.log" | wc -l)
    echo "  - 剩余日志文件: $remaining_logs 个"
fi

if [ -d "$REPORT_DIR" ]; then
    local remaining_reports=$(find "$REPORT_DIR" -type f | wc -l)
    echo "  - 剩余报告文件: $remaining_reports 个"
fi

local remaining_stacks=$(aws cloudformation list-stacks --region us-east-1 \
    --query "StackSummaries[?contains(StackName, 'payer') && StackStatus != 'DELETE_COMPLETE'].StackName" \
    --output text 2>/dev/null | wc -w)
echo "  - 剩余CloudFormation栈: $remaining_stacks 个"