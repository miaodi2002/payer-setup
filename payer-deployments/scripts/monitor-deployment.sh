#!/bin/bash

# 部署监控脚本
# 使用方法: ./monitor-deployment.sh <payer-id>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYER_DEPLOYMENTS_DIR="$(dirname "$SCRIPT_DIR")"
PAYER_ID="$1"

if [ -z "$PAYER_ID" ]; then
    echo "使用方法: $0 <payer-id>"
    exit 1
fi

LOG_DIR="$PAYER_DEPLOYMENTS_DIR/logs/$PAYER_ID"
REPORT_DIR="$PAYER_DEPLOYMENTS_DIR/reports/$PAYER_ID"

# 实时监控函数
monitor_logs() {
    local latest_log=$(find "$LOG_DIR" -name "deployment.log" -type f -exec ls -t1 {} + | head -1)
    
    if [ -f "$latest_log" ]; then
        echo "监控日志文件: $latest_log"
        echo "按Ctrl+C退出监控"
        tail -f "$latest_log"
    else
        echo "未找到日志文件"
        exit 1
    fi
}

# 显示当前状态
show_status() {
    echo "=== Payer $PAYER_ID 部署状态 ==="
    
    # 检查注册表状态
    if [ -f "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json" ]; then
        STATUS=$(jq -r ".payers[\"$PAYER_ID\"].deployment_status" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json")
        echo "注册表状态: $STATUS"
    fi
    
    # 检查最新日志
    if [ -d "$LOG_DIR" ]; then
        local latest_log=$(find "$LOG_DIR" -name "deployment.log" -type f -exec ls -t1 {} + | head -1)
        if [ -f "$latest_log" ]; then
            echo "最新日志: $latest_log"
            echo "最后几行日志:"
            tail -5 "$latest_log"
        fi
    fi
    
    # 检查CloudFormation栈
    echo ""
    echo "=== CloudFormation栈状态 ==="
    aws cloudformation list-stacks --region us-east-1 \
        --query "StackSummaries[?contains(StackName, 'payer') && StackStatus != 'DELETE_COMPLETE'].{Name:StackName,Status:StackStatus,Updated:LastUpdatedTime}" \
        --output table
}

case "${2:-status}" in
    "logs")
        monitor_logs
        ;;
    "status"|*)
        show_status
        ;;
esac