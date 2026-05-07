#!/bin/bash

################################################################################
# Elite-new17 Payer 部署脚本
#
# 用途: 完整部署 Elite-new17 Payer 的所有8个模块
# 使用方式:
#   1. 确保 AWS CLI 已配置 Elite-new17 profile
#   2. 执行: bash deploy-elite-new17.sh
#   3. 按照提示逐步完成部署
#
# 注意事项:
#   - 使用 AWS_PROFILE 环境变量指定 profile
#   - 每个模块部署后会提示确认是否继续
#   - 关键输出参数会保存到 Elite-new17-outputs.txt
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出文件
OUTPUT_FILE="../Elite-new17-outputs.txt"
LOG_FILE="../logs/Elite-new17-deployment-$(date +%Y%m%d-%H%M%S).log"

# 创建日志目录
mkdir -p ../logs

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# 确认函数
confirm() {
    read -p "$(echo -e ${YELLOW}$1${NC}) [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

################################################################################
# Phase 1: 环境初始化
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}         Elite-new17 Payer 部署脚本 - v1.0              ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始 Elite-new17 部署流程"

# 设置 AWS Profile
export AWS_PROFILE=Elite-new17
log_info "AWS Profile 设置为: $AWS_PROFILE"

# 验证 AWS 配置
log "验证 AWS CLI 配置..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_error "AWS CLI 配置验证失败！请检查 Elite-new17 profile 是否正确配置。"
    exit 1
fi

# 获取账户信息
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "✅ 账户ID: $ACCOUNT_ID"
echo "ACCOUNT_ID=$ACCOUNT_ID" > "$OUTPUT_FILE"

# 获取 ROOT_ID
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
log "✅ ROOT_ID: $ROOT_ID"
echo "ROOT_ID=$ROOT_ID" >> "$OUTPUT_FILE"

# 验证区域
REGION=$(aws configure get region)
if [ "$REGION" != "us-east-1" ]; then
    log_warning "当前区域是 $REGION，但 CUR 只能在 us-east-1 创建"
    log_warning "请确保已设置正确的区域"
fi
echo "REGION=$REGION" >> "$OUTPUT_FILE"

# 切换到工作目录
cd /Users/di.miao/Work/BIP/payer-setup/aws-payer-automation
log "✅ 工作目录: $(pwd)"

echo ""
log "环境初始化完成！"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if ! confirm "是否继续部署 Module 1?"; then
    log "用户取消部署"
    exit 0
fi

################################################################################
# Module 1: OU和SCP设置
################################################################################

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}                  Module 1: OU和SCP设置                  ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 1: OU和SCP设置"
START_TIME=$(date +%s)

./scripts/deploy-single.sh 1 --root-id $ROOT_ID

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "✅ Module 1 部署完成！耗时: ${DURATION}秒"

# 获取输出参数
log "获取 Module 1 输出参数..."
sleep 10  # 等待栈输出可用

NORMAL_OU_ID=$(aws cloudformation describe-stacks \
  --stack-name payer-*-ou-scp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`NormalOUId`].OutputValue' \
  --output text 2>/dev/null || echo "")

if [ -n "$NORMAL_OU_ID" ]; then
    log "✅ NormalOUId: $NORMAL_OU_ID"
    echo "NORMAL_OU_ID=$NORMAL_OU_ID" >> "$OUTPUT_FILE"
else
    log_warning "未能获取 NormalOUId，请手动检查"
fi

# 验证
log "验证 OU 结构..."
aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_ID \
  --query 'OrganizationalUnits[*].{Name:Name,Id:Id}' \
  --output table | tee -a "$LOG_FILE"

echo ""
if ! confirm "Module 1 部署成功，是否继续部署 Module 2?"; then
    log "用户暂停部署"
    exit 0
fi

################################################################################
# Module 2: BillingConductor设置
################################################################################

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}            Module 2: BillingConductor设置               ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 2: BillingConductor设置"

# 检查 BillingGroup 是否已存在
log "检查 BillingGroup 'Bills' 是否已存在..."
EXISTING_BG=$(aws billingconductor list-billing-groups \
  --query 'BillingGroups[?Name==`Bills`].Arn' \
  --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_BG" ]; then
    log_warning "BillingGroup 'Bills' 已存在，跳过部署"
    BILLING_GROUP_ARN=$EXISTING_BG
    log "✅ 使用现有 BillingGroupArn: $BILLING_GROUP_ARN"
    echo "BILLING_GROUP_ARN=$BILLING_GROUP_ARN" >> "$OUTPUT_FILE"
    echo "MODULE_2_STATUS=SKIPPED" >> "$OUTPUT_FILE"
else
    log "BillingGroup 不存在，开始部署..."
    START_TIME=$(date +%s)

    ./scripts/deploy-single.sh 2

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log "✅ Module 2 部署完成！耗时: ${DURATION}秒"

    # 获取输出参数
    sleep 10
    BILLING_GROUP_ARN=$(aws cloudformation describe-stacks \
      --stack-name payer-billing-conductor-* \
      --query 'Stacks[0].Outputs[?OutputKey==`BillingGroupArn`].OutputValue' \
      --output text 2>/dev/null || echo "")

    if [ -n "$BILLING_GROUP_ARN" ]; then
        log "✅ BillingGroupArn: $BILLING_GROUP_ARN"
        echo "BILLING_GROUP_ARN=$BILLING_GROUP_ARN" >> "$OUTPUT_FILE"
    else
        log_error "未能获取 BillingGroupArn！"
        exit 1
    fi
fi

echo ""
if ! confirm "Module 2 完成，是否继续部署 Module 3?"; then
    log "用户暂停部署"
    exit 0
fi

################################################################################
# Module 3: Pro forma CUR
################################################################################

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}               Module 3: Pro forma CUR                   ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 3: Pro forma CUR"
START_TIME=$(date +%s)

./scripts/deploy-single.sh 3 --billing-group-arn $BILLING_GROUP_ARN

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "✅ Module 3 部署完成！耗时: ${DURATION}秒"

# 获取输出参数
sleep 10
PROFORMA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-proforma-* \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text 2>/dev/null || echo "")

if [ -n "$PROFORMA_BUCKET" ]; then
    log "✅ ProformaBucket: $PROFORMA_BUCKET"
    echo "PROFORMA_BUCKET=$PROFORMA_BUCKET" >> "$OUTPUT_FILE"
else
    log_error "未能获取 ProformaBucket！"
    exit 1
fi

# 验证 S3 bucket
log "验证 S3 bucket..."
aws s3 ls | grep bip-cur | tee -a "$LOG_FILE"

echo ""
if ! confirm "Module 3 部署成功，是否继续部署 Module 4?"; then
    log "用户暂停部署"
    exit 0
fi

################################################################################
# Module 4: RISP CUR
################################################################################

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}                  Module 4: RISP CUR                     ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 4: RISP CUR"
START_TIME=$(date +%s)

./scripts/deploy-single.sh 4

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "✅ Module 4 部署完成！耗时: ${DURATION}秒"

# 获取输出参数
sleep 10
RISP_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name payer-cur-risp-* \
  --query 'Stacks[0].Outputs[?OutputKey==`RISPBucketName`].OutputValue' \
  --output text 2>/dev/null || echo "")

if [ -n "$RISP_BUCKET" ]; then
    log "✅ RISPBucket: $RISP_BUCKET"
    echo "RISP_BUCKET=$RISP_BUCKET" >> "$OUTPUT_FILE"
else
    log_error "未能获取 RISPBucket！"
    exit 1
fi

# 验证 S3 bucket
log "验证 RISP S3 bucket..."
aws s3 ls | grep bip-risp-cur | tee -a "$LOG_FILE"

echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}           ⚠️  Module 5 是关键模块，请仔细检查！          ${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if ! confirm "Module 4 部署成功，是否继续部署 Module 5 (CRITICAL)?"; then
    log "用户暂停部署"
    exit 0
fi

################################################################################
# Module 5: Athena Setup (CRITICAL)
################################################################################

echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}          Module 5: Athena Setup (CRITICAL)              ${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 5: Athena Setup (使用 v1.5)"

# 验证参数
log_info "参数验证:"
log_info "  ACCOUNT_ID: $ACCOUNT_ID"
log_info "  PROFORMA_BUCKET: $PROFORMA_BUCKET"
log_info "  RISP_BUCKET: $RISP_BUCKET"
log_info "  ProformaReportName: $ACCOUNT_ID (⚠️ 必须是账户ID，不能有proforma-前缀)"

if ! confirm "参数确认无误，开始部署?"; then
    log_error "用户取消部署，请检查参数"
    exit 1
fi

STACK_NAME=payer-Elite-new17-athena-setup-$(date +%s)
log "栈名称: $STACK_NAME"

START_TIME=$(date +%s)

./deployment-scripts/version-management.sh deploy 05-athena-setup v1.5 \
  $STACK_NAME \
  --parameters \
  ProformaBucketName=$PROFORMA_BUCKET \
  RISPBucketName=$RISP_BUCKET \
  ProformaReportName=$ACCOUNT_ID \
  RISPReportName=risp-$ACCOUNT_ID

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "✅ Module 5 部署完成！耗时: ${DURATION}秒"

# 关键验证步骤
echo ""
log_warning "开始关键验证步骤..."
sleep 15  # 等待资源创建完成

# 1. 检查 Crawler
log "1. 检查 Crawler 创建..."
CRAWLERS=$(aws glue list-crawlers --query 'CrawlerNames[?contains(@, `'$ACCOUNT_ID'`)]' --output text)
if [ -n "$CRAWLERS" ]; then
    log "✅ Crawler 已创建: $CRAWLERS"
    echo "CRAWLERS=$CRAWLERS" >> "$OUTPUT_FILE"
else
    log_error "Crawler 创建失败！"
fi

# 2. 验证 Crawler 路径（最关键）
log "2. 验证 Crawler 路径（最关键）..."
CRAWLER_PATH=$(aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.Targets.S3Targets[0].Path' \
  --output text 2>/dev/null || echo "")

if [ -n "$CRAWLER_PATH" ]; then
    log_info "Crawler 路径: $CRAWLER_PATH"
    echo "CRAWLER_PATH=$CRAWLER_PATH" >> "$OUTPUT_FILE"

    # 检查路径是否正确
    EXPECTED_PATH="s3://${PROFORMA_BUCKET}/daily/${ACCOUNT_ID}/"
    if [ "$CRAWLER_PATH" == "$EXPECTED_PATH" ]; then
        log "✅ Crawler 路径正确！"
    else
        log_error "⚠️ Crawler 路径不正确！"
        log_error "   期望: $EXPECTED_PATH"
        log_error "   实际: $CRAWLER_PATH"
        log_error "   请立即检查并修复！"
    fi
else
    log_error "无法获取 Crawler 路径！"
fi

# 3. 手动触发 Crawler
log "3. 手动触发 Crawler 测试..."
aws glue start-crawler --name AWSCURCrawler-$ACCOUNT_ID 2>/dev/null && \
    log "✅ Crawler 已触发" || \
    log_warning "Crawler 触发失败（可能已在运行）"

sleep 60
CRAWLER_STATE=$(aws glue get-crawler --name AWSCURCrawler-$ACCOUNT_ID \
  --query 'Crawler.State' \
  --output text 2>/dev/null || echo "UNKNOWN")
log "Crawler 状态: $CRAWLER_STATE"

# 4. 检查数据库和表
log "4. 检查 Glue Database..."
DATABASE_NAME="athenacurcfn_$ACCOUNT_ID"
TABLES=$(aws glue get-tables --database-name $DATABASE_NAME \
  --query 'TableList[*].Name' \
  --output text 2>/dev/null || echo "")

if [ -n "$TABLES" ]; then
    log "✅ 数据库表: $TABLES"
    echo "ATHENA_TABLES=$TABLES" >> "$OUTPUT_FILE"
else
    log_warning "暂无表（CUR 数据需要 24 小时生成）"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}    Module 5 验证完成！请确认 Crawler 路径正确无误！      ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if ! confirm "Module 5 部署和验证完成，是否继续部署 Module 6?"; then
    log "用户暂停部署"
    exit 0
fi

################################################################################
# Module 6: Account Auto Management
################################################################################

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}          Module 6: Account Auto Management              ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 6: Account Auto Management"
START_TIME=$(date +%s)

./scripts/deploy-single.sh 6 --normal-ou-id $NORMAL_OU_ID

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "✅ Module 6 部署完成！耗时: ${DURATION}秒"

# 验证
log "验证 Lambda 函数..."
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `AccountAutoMover`)].FunctionName' \
  --output table | tee -a "$LOG_FILE"

echo ""
if ! confirm "Module 6 部署成功，是否继续部署 Module 7?"; then
    log "用户暂停部署"
    exit 0
fi

################################################################################
# Module 7: CloudFront Monitoring
################################################################################

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}           Module 7: CloudFront Monitoring               ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 7: CloudFront Monitoring (阈值: 5GB)"
START_TIME=$(date +%s)

./scripts/deploy-single.sh 7 \
  --payer-name "Elite-new17" \
  --threshold-mb 5120

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "✅ Module 7 部署完成！耗时: ${DURATION}秒"

# 验证
log "验证 OAM Sink..."
aws oam list-sinks --output table | tee -a "$LOG_FILE"

log "验证 CloudWatch 告警..."
aws cloudwatch describe-alarms \
  --alarm-names "*CloudFront*" \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table | tee -a "$LOG_FILE"

echo ""
if ! confirm "Module 7 部署成功，是否继续部署 Module 8 (最后一个模块)?"; then
    log "用户暂停部署"
    exit 0
fi

################################################################################
# Module 8: IAM Users
################################################################################

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}                 Module 8: IAM Users                     ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log "开始部署 Module 8: IAM Users"
START_TIME=$(date +%s)

./deployment-scripts/version-management.sh deploy 08-iam-users v1.5 \
  payer-Elite-new17-iam-users-$(date +%s)

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "✅ Module 8 部署完成！耗时: ${DURATION}秒"

# 验证
log "验证 IAM 用户..."
aws iam list-users \
  --query 'Users[?contains(UserName, `cost_explorer`) || contains(UserName, `ReadOnly`)].UserName' \
  --output table | tee -a "$LOG_FILE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}            所有模块部署完成！开始最终验证...             ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

################################################################################
# 最终验证
################################################################################

log "执行最终验证..."

# 1. 检查所有栈状态
log "1. 检查所有 CloudFormation 栈状态..."
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `payer`)].{Name:StackName,Status:StackStatus,Time:CreationTime}' \
  --output table | tee -a "$LOG_FILE"

# 2. 验证 OU 结构
log "2. 验证组织结构..."
aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_ID \
  --query 'OrganizationalUnits[*].{Name:Name,Id:Id}' \
  --output table | tee -a "$LOG_FILE"

# 3. 统计信息
TOTAL_STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `payer`)] | length(@)' \
  --output text)

log "✅ 部署完成统计:"
log "   - 成功创建的栈: $TOTAL_STACKS"
log "   - 账户ID: $ACCOUNT_ID"
log "   - 输出文件: $OUTPUT_FILE"
log "   - 日志文件: $LOG_FILE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                   🎉 部署全部完成！ 🎉                  ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}重要提醒:${NC}"
echo -e "  1. CUR 数据需要 24 小时才能生成首次数据"
echo -e "  2. IAM 用户默认密码: ${RED}Password1!${NC} (首次登录需修改)"
echo -e "  3. 请检查部署文档: ${BLUE}Elite-new17-DEPLOYMENT-STATUS.md${NC}"
echo -e "  4. 输出参数已保存到: ${BLUE}$OUTPUT_FILE${NC}"
echo -e "  5. 完整日志已保存到: ${BLUE}$LOG_FILE${NC}"
echo ""
echo -e "${BLUE}下一步操作:${NC}"
echo -e "  - 更新部署状态文档并记录所有输出参数"
echo -e "  - 24小时后验证 Athena 数据查询"
echo -e "  - 通知用户修改 IAM 初始密码"
echo -e "  - 测试账户自动移动和 CloudFront 监控功能"
echo ""

log "Elite-new17 部署流程全部完成！"
