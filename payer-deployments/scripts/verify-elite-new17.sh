#!/bin/bash

################################################################################
# Elite-new17 Payer 验证脚本
#
# 用途: 验证 Elite-new17 Payer 部署的完整性和正确性
# 使用方式:
#   1. 确保已完成所有模块部署
#   2. 执行: bash verify-elite-new17.sh
#   3. 查看生成的验证报告
#
# 验证内容:
#   - CloudFormation 栈状态
#   - OU 组织结构
#   - S3 Buckets
#   - Glue Crawler 路径（关键）
#   - Lambda 函数
#   - IAM 用户
#   - Athena 数据查询（24小时后）
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 报告文件
REPORT_FILE="../reports/Elite-new17-verification-$(date +%Y%m%d-%H%M%S).txt"

# 创建报告目录
mkdir -p ../reports

# 计数器
PASS_COUNT=0
FAIL_COUNT=0
WARNING_COUNT=0

# 日志函数
log() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$REPORT_FILE"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$REPORT_FILE"
    ((FAIL_COUNT++))
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$REPORT_FILE"
    ((WARNING_COUNT++))
}

log_info() {
    echo -e "${BLUE}[i]${NC} $1" | tee -a "$REPORT_FILE"
}

section() {
    echo "" | tee -a "$REPORT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$REPORT_FILE"
    echo "$1" | tee -a "$REPORT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

################################################################################
# 开始验证
################################################################################

section "Elite-new17 Payer 部署验证报告"

log_info "验证时间: $(date '+%Y-%m-%d %H:%M:%S')"
log_info "报告文件: $REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 设置 AWS Profile
export AWS_PROFILE=Elite-new17

# 获取账户信息
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "ERROR")
if [ "$ACCOUNT_ID" == "ERROR" ]; then
    log_fail "无法获取账户ID - AWS CLI配置可能有问题"
    exit 1
else
    log "账户ID: $ACCOUNT_ID"
fi

ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text 2>/dev/null || echo "ERROR")
if [ "$ROOT_ID" == "ERROR" ]; then
    log_fail "无法获取 ROOT_ID"
else
    log "ROOT_ID: $ROOT_ID"
fi

################################################################################
# 1. CloudFormation 栈状态检查
################################################################################

section "1. CloudFormation 栈状态检查"

log_info "检查所有 payer 相关的栈..."

# 获取所有栈
STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE CREATE_FAILED ROLLBACK_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `payer`)].{Name:StackName,Status:StackStatus}' \
  --output text 2>/dev/null || echo "")

if [ -z "$STACKS" ]; then
    log_fail "未找到任何 payer 相关的栈"
else
    echo "$STACKS" | tee -a "$REPORT_FILE"

    # 统计栈状态
    COMPLETE_COUNT=$(echo "$STACKS" | grep -c "CREATE_COMPLETE" || echo "0")
    FAILED_COUNT=$(echo "$STACKS" | grep -c "CREATE_FAILED\|ROLLBACK" || echo "0")

    log_info "CREATE_COMPLETE 栈数量: $COMPLETE_COUNT"

    if [ "$COMPLETE_COUNT" -eq 8 ]; then
        log "所有8个模块栈都已成功创建"
    elif [ "$COMPLETE_COUNT" -gt 0 ]; then
        log_warning "只有 $COMPLETE_COUNT 个栈成功创建（期望8个）"
    else
        log_fail "没有成功创建的栈"
    fi

    if [ "$FAILED_COUNT" -gt 0 ]; then
        log_fail "发现 $FAILED_COUNT 个失败的栈"
    fi
fi

################################################################################
# 2. OU 组织结构验证
################################################################################

section "2. OU 组织结构验证"

log_info "检查 OU 结构..."

OUS=$(aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_ID \
  --query 'OrganizationalUnits[*].Name' \
  --output text 2>/dev/null || echo "")

if [ -z "$OUS" ]; then
    log_fail "未找到任何 OU"
else
    echo "已创建的 OU: $OUS" | tee -a "$REPORT_FILE"

    # 检查必需的OU
    if echo "$OUS" | grep -q "Free"; then
        log "Free OU 已创建"
    else
        log_fail "Free OU 未找到"
    fi

    if echo "$OUS" | grep -q "Block"; then
        log "Block OU 已创建"
    else
        log_fail "Block OU 未找到"
    fi

    if echo "$OUS" | grep -q "Normal"; then
        log "Normal OU 已创建"
    else
        log_fail "Normal OU 未找到"
    fi
fi

# 检查 SCP 策略
log_info "检查 SCP 策略..."
SCP_COUNT=$(aws organizations list-policies \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[*].Name' \
  --output text 2>/dev/null | wc -w || echo "0")

if [ "$SCP_COUNT" -ge 7 ]; then
    log "SCP 策略数量: $SCP_COUNT (期望至少7个)"
else
    log_warning "SCP 策略数量: $SCP_COUNT (期望至少7个)"
fi

################################################################################
# 3. BillingConductor 验证
################################################################################

section "3. BillingConductor 验证"

log_info "检查 BillingGroup..."

BG_ARN=$(aws billingconductor list-billing-groups \
  --query 'BillingGroups[?Name==`Bills`].Arn' \
  --output text 2>/dev/null || echo "")

if [ -n "$BG_ARN" ]; then
    log "BillingGroup 'Bills' 已存在"
    log_info "ARN: $BG_ARN"
else
    log_fail "BillingGroup 'Bills' 未找到"
fi

################################################################################
# 4. S3 Buckets 验证
################################################################################

section "4. S3 Buckets 验证"

log_info "检查 Pro forma CUR bucket..."

PROFORMA_BUCKET="bip-cur-$ACCOUNT_ID"
if aws s3 ls "s3://$PROFORMA_BUCKET" > /dev/null 2>&1; then
    log "Pro forma bucket 已创建: $PROFORMA_BUCKET"

    # 检查 bucket 内容
    OBJECTS=$(aws s3 ls "s3://$PROFORMA_BUCKET/" --recursive 2>/dev/null | wc -l || echo "0")
    log_info "Bucket 对象数: $OBJECTS"
else
    log_fail "Pro forma bucket 不存在: $PROFORMA_BUCKET"
fi

log_info "检查 RISP CUR bucket..."

RISP_BUCKET="bip-risp-cur-$ACCOUNT_ID"
if aws s3 ls "s3://$RISP_BUCKET" > /dev/null 2>&1; then
    log "RISP bucket 已创建: $RISP_BUCKET"

    # 检查 bucket 内容
    OBJECTS=$(aws s3 ls "s3://$RISP_BUCKET/" --recursive 2>/dev/null | wc -l || echo "0")
    log_info "Bucket 对象数: $OBJECTS"
else
    log_fail "RISP bucket 不存在: $RISP_BUCKET"
fi

################################################################################
# 5. Glue Crawler 验证（关键）
################################################################################

section "5. Glue Crawler 验证 ⚠️ CRITICAL"

log_info "检查 Glue Database..."

DATABASE_NAME="athenacurcfn_$ACCOUNT_ID"
if aws glue get-database --name $DATABASE_NAME > /dev/null 2>&1; then
    log "Glue Database 已创建: $DATABASE_NAME"
else
    log_fail "Glue Database 不存在: $DATABASE_NAME"
fi

log_info "检查 Crawler..."

CRAWLERS=$(aws glue list-crawlers \
  --query 'CrawlerNames[?contains(@, `'$ACCOUNT_ID'`)]' \
  --output text 2>/dev/null || echo "")

if [ -n "$CRAWLERS" ]; then
    log "Crawler 已创建: $CRAWLERS"

    # 检查 Pro forma Crawler 路径（最关键的验证）
    log_info ""
    log_info "⚠️ 验证 Pro forma Crawler 路径（最关键）..."

    PROFORMA_CRAWLER="AWSCURCrawler-$ACCOUNT_ID"
    CRAWLER_PATH=$(aws glue get-crawler --name $PROFORMA_CRAWLER \
      --query 'Crawler.Targets.S3Targets[0].Path' \
      --output text 2>/dev/null || echo "")

    if [ -n "$CRAWLER_PATH" ]; then
        log_info "Crawler 路径: $CRAWLER_PATH"

        # 验证路径格式
        EXPECTED_PATH="s3://${PROFORMA_BUCKET}/daily/${ACCOUNT_ID}/"
        WRONG_PATH="s3://${PROFORMA_BUCKET}/daily/proforma-${ACCOUNT_ID}/"

        if [ "$CRAWLER_PATH" == "$EXPECTED_PATH" ]; then
            log "✅ Crawler 路径正确！"
            log_info "   路径: $CRAWLER_PATH"
        elif [ "$CRAWLER_PATH" == "$WRONG_PATH" ]; then
            log_fail "❌ Crawler 路径错误！包含 proforma- 前缀"
            log_fail "   错误路径: $CRAWLER_PATH"
            log_fail "   正确路径: $EXPECTED_PATH"
            log_fail "   这会导致 Athena 查询无数据！请立即修复！"
        else
            log_warning "Crawler 路径格式异常"
            log_warning "   实际: $CRAWLER_PATH"
            log_warning "   期望: $EXPECTED_PATH"
        fi
    else
        log_fail "无法获取 Crawler 路径"
    fi

    # 检查 Crawler 状态
    CRAWLER_STATE=$(aws glue get-crawler --name $PROFORMA_CRAWLER \
      --query 'Crawler.State' \
      --output text 2>/dev/null || echo "UNKNOWN")
    log_info "Crawler 状态: $CRAWLER_STATE"

    # 检查 RISP Crawler (模板创建的名字使用大写 RISP)
    RISP_CRAWLER="AWSCURCrawler-RISP-$ACCOUNT_ID"
    if aws glue get-crawler --name $RISP_CRAWLER > /dev/null 2>&1; then
        log "RISP Crawler 已创建: $RISP_CRAWLER"
    else
        log_warning "RISP Crawler 未找到: $RISP_CRAWLER"
    fi
else
    log_fail "未找到任何 Crawler"
fi

# 检查表
log_info "检查 Glue Tables..."

TABLES=$(aws glue get-tables --database-name $DATABASE_NAME \
  --query 'TableList[*].Name' \
  --output text 2>/dev/null || echo "")

if [ -n "$TABLES" ]; then
    log "已创建的表: $TABLES"
    TABLE_COUNT=$(echo "$TABLES" | wc -w)
    log_info "表数量: $TABLE_COUNT"
else
    log_warning "暂无表（CUR 数据需要 24 小时生成）"
fi

################################################################################
# 6. Lambda 函数验证
################################################################################

section "6. Lambda 函数验证"

log_info "检查 Lambda 函数..."

# Athena Setup Lambda
ATHENA_LAMBDA=$(aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `Athena`) || contains(FunctionName, `CUR`)].FunctionName' \
  --output text 2>/dev/null || echo "")

if [ -n "$ATHENA_LAMBDA" ]; then
    log "Athena Setup Lambda: $ATHENA_LAMBDA"
else
    log_warning "未找到 Athena Setup Lambda"
fi

# Account Auto Mover Lambda
AUTO_MOVER_LAMBDA=$(aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `AccountAutoMover`) || contains(FunctionName, `Account`)].FunctionName' \
  --output text 2>/dev/null || echo "")

if [ -n "$AUTO_MOVER_LAMBDA" ]; then
    log "Account Auto Mover Lambda: $AUTO_MOVER_LAMBDA"
else
    log_warning "未找到 Account Auto Mover Lambda"
fi

# CloudFront Monitoring Lambda
CLOUDFRONT_LAMBDA=$(aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `CloudFront`) || contains(FunctionName, `OAM`)].FunctionName' \
  --output text 2>/dev/null || echo "")

if [ -n "$CLOUDFRONT_LAMBDA" ]; then
    log "CloudFront Monitoring Lambda: $CLOUDFRONT_LAMBDA"
else
    log_warning "未找到 CloudFront Monitoring Lambda"
fi

################################################################################
# 7. OAM 和 CloudWatch 验证
################################################################################

section "7. OAM 和 CloudWatch 验证"

log_info "检查 OAM Sink..."

OAM_SINKS=$(aws oam list-sinks \
  --query 'Items[*].Name' \
  --output text 2>/dev/null || echo "")

if [ -n "$OAM_SINKS" ]; then
    log "OAM Sink 已创建: $OAM_SINKS"
else
    log_warning "未找到 OAM Sink"
fi

log_info "检查 CloudWatch 告警..."

ALARMS=$(aws cloudwatch describe-alarms \
  --query 'MetricAlarms[?contains(AlarmName, `CloudFront`)].{Name:AlarmName,State:StateValue}' \
  --output text 2>/dev/null || echo "")

if [ -n "$ALARMS" ]; then
    log "CloudWatch 告警已创建"
    echo "$ALARMS" | tee -a "$REPORT_FILE"
else
    log_warning "未找到 CloudFront 告警"
fi

################################################################################
# 8. IAM 用户验证
################################################################################

section "8. IAM 用户验证"

log_info "检查 IAM 用户..."

USERS=$(aws iam list-users \
  --query 'Users[?contains(UserName, `cost_explorer`) || contains(UserName, `ReadOnly`)].UserName' \
  --output text 2>/dev/null || echo "")

if [ -n "$USERS" ]; then
    log "IAM 用户已创建: $USERS"

    if echo "$USERS" | grep -q "cost_explorer"; then
        log "cost_explorer 用户已创建"
    else
        log_fail "cost_explorer 用户未找到"
    fi

    if echo "$USERS" | grep -q "ReadOnly"; then
        log "ReadOnly_system 用户已创建"
    else
        log_fail "ReadOnly_system 用户未找到"
    fi
else
    log_fail "未找到任何 IAM 用户"
fi

################################################################################
# 9. Athena 查询测试（可选 - 24小时后才有数据）
################################################################################

section "9. Athena 数据查询测试"

log_info "尝试查询 Athena 表（仅在有数据时有效）..."

if [ -n "$TABLES" ]; then
    log_info "发现表，尝试查询..."

    # 创建临时查询结果位置（如果不存在）
    QUERY_RESULTS_BUCKET="athena-query-results-$ACCOUNT_ID"

    # 简单的计数查询
    QUERY="SELECT COUNT(*) as record_count FROM $DATABASE_NAME.$ACCOUNT_ID LIMIT 1"
    log_info "查询: $QUERY"

    # 注意：这里只是测试查询能否执行，不等待结果
    QUERY_ID=$(aws athena start-query-execution \
      --query-string "$QUERY" \
      --query-execution-context Database=$DATABASE_NAME \
      --result-configuration "OutputLocation=s3://${PROFORMA_BUCKET}/athena-results/" \
      --query 'QueryExecutionId' \
      --output text 2>/dev/null || echo "")

    if [ -n "$QUERY_ID" ]; then
        log "Athena 查询已提交: $QUERY_ID"
        log_info "注意：首次 CUR 数据需要 24 小时生成"
    else
        log_warning "Athena 查询提交失败（可能是因为还没有数据）"
    fi
else
    log_warning "跳过 Athena 查询测试（没有表）"
    log_info "CUR 数据需要 24 小时生成，请稍后再测试"
fi

################################################################################
# 生成总结报告
################################################################################

section "验证总结"

TOTAL_CHECKS=$((PASS_COUNT + FAIL_COUNT + WARNING_COUNT))

echo "" | tee -a "$REPORT_FILE"
echo "总检查项: $TOTAL_CHECKS" | tee -a "$REPORT_FILE"
echo -e "${GREEN}通过: $PASS_COUNT${NC}" | tee -a "$REPORT_FILE"
echo -e "${RED}失败: $FAIL_COUNT${NC}" | tee -a "$REPORT_FILE"
echo -e "${YELLOW}警告: $WARNING_COUNT${NC}" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if [ $FAIL_COUNT -eq 0 ] && [ $WARNING_COUNT -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    echo -e "${GREEN}    ✅ Elite-new17 部署验证全部通过！                    ${NC}" | tee -a "$REPORT_FILE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
elif [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    echo -e "${YELLOW}    ⚠️  验证通过，但有 $WARNING_COUNT 个警告需要关注      ${NC}" | tee -a "$REPORT_FILE"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    echo -e "${RED}    ❌ 发现 $FAIL_COUNT 个问题，需要立即处理！              ${NC}" | tee -a "$REPORT_FILE"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
fi

echo "" | tee -a "$REPORT_FILE"
echo "完整报告已保存到: $REPORT_FILE" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 退出码
if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
