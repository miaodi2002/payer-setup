#!/bin/bash

# 部署报告生成脚本
# 使用方法: ./generate-report.sh <payer-id> [--format html|md|json]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYER_DEPLOYMENTS_DIR="$(dirname "$SCRIPT_DIR")"
PAYER_ID="$1"
FORMAT="${2:-md}"

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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ -z "$PAYER_ID" ]; then
    echo "使用方法: $0 <payer-id> [--format html|md|json]"
    exit 1
fi

# 解析格式参数
if [ "$2" = "--format" ] && [ -n "$3" ]; then
    FORMAT="$3"
fi

LOG_DIR="$PAYER_DEPLOYMENTS_DIR/logs/$PAYER_ID"
REPORT_DIR="$PAYER_DEPLOYMENTS_DIR/reports/$PAYER_ID"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 验证Payer ID
if ! jq -e ".payers[\"$PAYER_ID\"]" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json" > /dev/null; then
    log_error "Payer ID '$PAYER_ID' 在注册表中不存在"
    exit 1
fi

log_info "为 Payer $PAYER_ID 生成 $FORMAT 格式报告..."

# 获取Payer信息
PAYER_INFO=$(jq -r ".payers[\"$PAYER_ID\"]" "$PAYER_DEPLOYMENTS_DIR/config/payer-registry.json")
COMPANY_NAME=$(echo "$PAYER_INFO" | jq -r ".company")
DEPLOYMENT_STATUS=$(echo "$PAYER_INFO" | jq -r ".deployment_status")

# 收集部署统计信息
collect_deployment_stats() {
    local total_deployments=0
    local successful_deployments=0
    local failed_deployments=0
    
    if [ -d "$LOG_DIR" ]; then
        total_deployments=$(find "$LOG_DIR" -name "deployment.log" | wc -l)
        
        # 分析日志中的成功/失败状态
        for log_file in $(find "$LOG_DIR" -name "deployment.log"); do
            if grep -q "部署完成" "$log_file" 2>/dev/null; then
                ((successful_deployments++))
            else
                ((failed_deployments++))
            fi
        done
    fi
    
    echo "$total_deployments|$successful_deployments|$failed_deployments"
}

# 获取CloudFormation栈状态
get_cf_stacks() {
    aws cloudformation list-stacks --region us-east-1 \
        --query "StackSummaries[?contains(StackName, 'payer') && StackStatus != 'DELETE_COMPLETE'].{Name:StackName,Status:StackStatus,Updated:LastUpdatedTime}" \
        --output json 2>/dev/null || echo "[]"
}

# 生成Markdown报告
generate_markdown_report() {
    local output_file="$REPORT_DIR/deployment-summary-$TIMESTAMP.md"
    local stats=$(collect_deployment_stats)
    local total=$(echo "$stats" | cut -d'|' -f1)
    local successful=$(echo "$stats" | cut -d'|' -f2)
    local failed=$(echo "$stats" | cut -d'|' -f3)
    
    cat > "$output_file" << EOF
# Payer $PAYER_ID 部署汇总报告

**生成时间**: $(date)
**报告类型**: 部署汇总

## 基本信息
- **Payer ID**: $PAYER_ID
- **公司名称**: $COMPANY_NAME
- **当前状态**: $DEPLOYMENT_STATUS

## 部署统计
- **总部署次数**: $total
- **成功部署**: $successful
- **失败部署**: $failed
- **成功率**: $(( total > 0 ? successful * 100 / total : 0 ))%

## CloudFormation栈状态
EOF

    # 添加CloudFormation栈信息
    local cf_stacks=$(get_cf_stacks)
    if [ "$cf_stacks" != "[]" ]; then
        echo "$cf_stacks" | jq -r '.[] | "- **\(.Name)**: \(.Status) (更新时间: \(.Updated // "N/A"))"' >> "$output_file"
    else
        echo "- 暂无CloudFormation栈" >> "$output_file"
    fi

    cat >> "$output_file" << EOF

## 最近部署日志
EOF

    # 添加最近的部署日志摘要
    if [ -d "$LOG_DIR" ]; then
        local latest_log=$(find "$LOG_DIR" -name "deployment.log" -type f -exec ls -t {} + | head -1)
        if [ -f "$latest_log" ]; then
            echo "### 最新部署日志 ($(basename $(dirname "$latest_log")))" >> "$output_file"
            echo '```' >> "$output_file"
            tail -20 "$latest_log" >> "$output_file"
            echo '```' >> "$output_file"
        fi
    fi

    cat >> "$output_file" << EOF

## 建议和下一步
- 定期检查CloudFormation栈状态
- 监控Athena数据库数据分离
- 验证BillingGroup配置正确性

---
*报告自动生成于 $(date)*
EOF

    echo "$output_file"
}

# 生成JSON报告
generate_json_report() {
    local output_file="$REPORT_DIR/deployment-summary-$TIMESTAMP.json"
    local stats=$(collect_deployment_stats)
    local total=$(echo "$stats" | cut -d'|' -f1)
    local successful=$(echo "$stats" | cut -d'|' -f2)
    local failed=$(echo "$stats" | cut -d'|' -f3)
    local cf_stacks=$(get_cf_stacks)
    
    cat > "$output_file" << EOF
{
  "report_metadata": {
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "payer_id": "$PAYER_ID",
    "company_name": "$COMPANY_NAME",
    "format": "json"
  },
  "deployment_status": {
    "current_status": "$DEPLOYMENT_STATUS",
    "total_deployments": $total,
    "successful_deployments": $successful,
    "failed_deployments": $failed,
    "success_rate": $(( total > 0 ? successful * 100 / total : 0 ))
  },
  "cloudformation_stacks": $cf_stacks,
  "log_directories": [
EOF

    # 添加日志目录列表
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -type d -name "????????_??????" | sort -r | head -10 | \
        while IFS= read -r dir; do
            echo "    \"$(basename "$dir")\","
        done | sed '$ s/,$//'
    fi

    cat >> "$output_file" << EOF
  ],
  "recommendations": [
    "定期检查CloudFormation栈状态",
    "监控Athena数据库数据分离",
    "验证BillingGroup配置正确性"
  ]
}
EOF

    echo "$output_file"
}

# 生成HTML报告
generate_html_report() {
    local output_file="$REPORT_DIR/deployment-summary-$TIMESTAMP.html"
    local stats=$(collect_deployment_stats)
    local total=$(echo "$stats" | cut -d'|' -f1)
    local successful=$(echo "$stats" | cut -d'|' -f2)
    local failed=$(echo "$stats" | cut -d'|' -f3)
    
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Payer $PAYER_ID 部署报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .stats { display: flex; gap: 20px; margin: 20px 0; }
        .stat-card { background-color: #e8f4fd; padding: 15px; border-radius: 5px; flex: 1; }
        .success { background-color: #d4edda; }
        .danger { background-color: #f8d7da; }
        .table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .table th, .table td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        .table th { background-color: #f2f2f2; }
        pre { background-color: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Payer $PAYER_ID 部署汇总报告</h1>
        <p><strong>生成时间</strong>: $(date)</p>
        <p><strong>公司名称</strong>: $COMPANY_NAME</p>
        <p><strong>当前状态</strong>: $DEPLOYMENT_STATUS</p>
    </div>

    <div class="stats">
        <div class="stat-card">
            <h3>总部署次数</h3>
            <h2>$total</h2>
        </div>
        <div class="stat-card success">
            <h3>成功部署</h3>
            <h2>$successful</h2>
        </div>
        <div class="stat-card danger">
            <h3>失败部署</h3>
            <h2>$failed</h2>
        </div>
        <div class="stat-card">
            <h3>成功率</h3>
            <h2>$(( total > 0 ? successful * 100 / total : 0 ))%</h2>
        </div>
    </div>

    <h2>CloudFormation栈状态</h2>
    <table class="table">
        <thead>
            <tr>
                <th>栈名称</th>
                <th>状态</th>
                <th>更新时间</th>
            </tr>
        </thead>
        <tbody>
EOF

    # 添加CloudFormation栈表格行
    local cf_stacks=$(get_cf_stacks)
    if [ "$cf_stacks" != "[]" ]; then
        echo "$cf_stacks" | jq -r '.[] | "<tr><td>\(.Name)</td><td>\(.Status)</td><td>\(.Updated // "N/A")</td></tr>"' >> "$output_file"
    else
        echo "<tr><td colspan=\"3\">暂无CloudFormation栈</td></tr>" >> "$output_file"
    fi

    cat >> "$output_file" << EOF
        </tbody>
    </table>

    <h2>最近部署日志</h2>
EOF

    # 添加最近的部署日志
    if [ -d "$LOG_DIR" ]; then
        local latest_log=$(find "$LOG_DIR" -name "deployment.log" -type f -exec ls -t {} + | head -1)
        if [ -f "$latest_log" ]; then
            echo "<h3>最新部署日志 ($(basename $(dirname "$latest_log")))</h3>" >> "$output_file"
            echo "<pre>" >> "$output_file"
            tail -20 "$latest_log" >> "$output_file"
            echo "</pre>" >> "$output_file"
        fi
    fi

    cat >> "$output_file" << EOF

    <h2>建议和下一步</h2>
    <ul>
        <li>定期检查CloudFormation栈状态</li>
        <li>监控Athena数据库数据分离</li>
        <li>验证BillingGroup配置正确性</li>
    </ul>

    <hr>
    <p><em>报告自动生成于 $(date)</em></p>
</body>
</html>
EOF

    echo "$output_file"
}

# 创建报告目录
mkdir -p "$REPORT_DIR"

# 根据格式生成报告
case "$FORMAT" in
    "md"|"markdown")
        REPORT_FILE=$(generate_markdown_report)
        ;;
    "json")
        REPORT_FILE=$(generate_json_report)
        ;;
    "html")
        REPORT_FILE=$(generate_html_report)
        ;;
    *)
        log_error "不支持的格式: $FORMAT (支持: md, json, html)"
        exit 1
        ;;
esac

log_success "报告已生成: $REPORT_FILE"

# 显示报告路径和预览
if [ "$FORMAT" = "md" ]; then
    echo ""
    echo "报告预览:"
    echo "========================"
    head -20 "$REPORT_FILE"
    echo "========================"
elif [ "$FORMAT" = "html" ]; then
    echo ""
    echo "HTML报告已生成，可在浏览器中打开查看"
fi

echo ""
echo "完整报告路径: $REPORT_FILE"