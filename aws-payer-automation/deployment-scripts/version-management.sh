#!/bin/bash
# Payer部署模板版本管理增强脚本
# 版本: 1.0
# 创建时间: 2025-07-24

# ==============================================================================
# 版本管理核心函数
# ==============================================================================

# 设置基础路径
TEMPLATE_BASE_PATH="/Users/di.miao/Work/payer-setup/aws-payer-automation/templates"
VERSION_REGISTRY="$TEMPLATE_BASE_PATH/version-registry.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# ==============================================================================
# 版本查询和验证函数
# ==============================================================================

# 列出所有可用版本
list_versions() {
    log_info "可用的模板版本:"
    
    if [ ! -f "$VERSION_REGISTRY" ]; then
        log_error "版本注册表不存在: $VERSION_REGISTRY"
        return 1
    fi
    
    echo "----------------------------------------"
    jq -r '.versions | to_entries[] | "版本: \(.key) | 状态: \(.value.status) | 描述: \(.value.description)"' "$VERSION_REGISTRY"
    echo "----------------------------------------"
    
    local current_version=$(jq -r '.current_version' "$VERSION_REGISTRY")
    log_info "当前推荐版本: $current_version"
}

# 获取指定版本的模块信息
get_version_info() {
    local version=$1
    
    if [ -z "$version" ]; then
        log_error "请指定版本号"
        return 1
    fi
    
    log_info "版本 $version 的详细信息:"
    jq -r ".versions.\"$version\"" "$VERSION_REGISTRY" 2>/dev/null || {
        log_error "版本 $version 不存在"
        return 1
    }
}

# 检查版本状态
check_version_status() {
    local version=$1
    
    if [ -z "$version" ]; then
        log_error "请指定版本号"
        return 1
    fi
    
    local status=$(jq -r ".versions.\"$version\".status" "$VERSION_REGISTRY" 2>/dev/null)
    
    case "$status" in
        "stable")
            log_success "版本 $version 状态: 稳定 (推荐使用)"
            return 0
            ;;
        "deprecated")
            log_warning "版本 $version 状态: 已弃用 (不推荐使用)"
            return 1
            ;;
        "beta")
            log_warning "版本 $version 状态: 测试版 (谨慎使用)"
            return 2
            ;;
        "null"|"")
            log_error "版本 $version 不存在"
            return 3
            ;;
        *)
            log_warning "版本 $version 状态: $status (未知状态)"
            return 4
            ;;
    esac
}

# ==============================================================================
# 模板路径解析函数
# ==============================================================================

# 获取指定版本和模块的模板路径
get_template_path() {
    local version=$1
    local module=$2
    local template_name=$3
    
    if [ -z "$version" ] || [ -z "$module" ]; then
        log_error "使用方法: get_template_path <version> <module> [template_name]"
        return 1
    fi
    
    # 标准化模块名称
    case "$module" in
        1|"module1"|"ou-scp") module="01-ou-scp" ;;
        2|"module2"|"billing") module="02-billing-conductor" ;;
        3|"module3"|"proforma") module="03-cur-proforma" ;;
        4|"module4"|"risp") module="04-cur-risp" ;;
        5|"module5"|"athena") module="05-athena-setup" ;;
        6|"module6"|"account") module="06-account-auto-management" ;;
        7|"module7"|"cloudfront") module="07-cloudfront-monitoring" ;;
    esac
    
    # 构建路径
    local base_path
    if [ "$version" = "current" ]; then
        base_path="$TEMPLATE_BASE_PATH/current/$module"
    else
        base_path="$TEMPLATE_BASE_PATH/versions/$version/$module"
    fi
    
    # 检查路径是否存在
    if [ ! -d "$base_path" ]; then
        log_error "模板路径不存在: $base_path"
        return 1
    fi
    
    # 如果指定了模板名称
    if [ -n "$template_name" ]; then
        local full_path="$base_path/$template_name"
        if [ ! -f "$full_path" ]; then
            log_error "模板文件不存在: $full_path"
            return 1
        fi
        echo "$full_path"
    else
        # 返回目录路径
        echo "$base_path"
    fi
}

# 获取模块的主要模板文件
get_main_template() {
    local version=$1
    local module=$2
    
    local module_path=$(get_template_path "$version" "$module")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 查找主要模板文件（排除README）
    local main_template
    case "$module" in
        "01-ou-scp")
            main_template="auto_SCP_1.yaml"
            ;;
        "02-billing-conductor")
            main_template="billing_conductor.yaml"
            ;;
        "03-cur-proforma")
            main_template="cur_export_proforma.yaml"
            ;;
        "04-cur-risp")
            main_template="cur_export_risp.yaml"
            ;;
        "05-athena-setup")
            main_template="athena_setup.yaml"
            ;;
        "06-account-auto-management")
            main_template="account_auto_move.yaml"
            ;;
        "07-cloudfront-monitoring")
            main_template="cloudfront_monitoring.yaml"
            ;;
        *)
            log_error "未知模块: $module"
            return 1
            ;;
    esac
    
    local full_path="$module_path/$main_template"
    if [ ! -f "$full_path" ]; then
        log_error "主模板文件不存在: $full_path"
        return 1
    fi
    
    echo "$full_path"
}

# ==============================================================================
# 增强的部署函数
# ==============================================================================

# 版本化部署函数
deploy_module_with_version() {
    local module=$1
    local version=$2
    local stack_name=$3
    local parameters=("${@:4}")
    
    if [ -z "$module" ] || [ -z "$version" ] || [ -z "$stack_name" ]; then
        log_error "使用方法: deploy_module_with_version <module> <version> <stack_name> [parameters...]"
        return 1
    fi
    
    # 检查版本状态
    if ! check_version_status "$version"; then
        if [ "$version" != "current" ]; then
            log_warning "使用非推荐版本 $version 进行部署"
            read -p "确认继续部署? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "部署已取消"
                return 1
            fi
        fi
    fi
    
    # 获取模板路径
    local template_path=$(get_main_template "$version" "$module")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    log_info "开始部署模块 $module (版本: $version)"
    log_info "模板路径: $template_path"
    log_info "栈名称: $stack_name"
    
    # 构建AWS CLI命令
    local aws_cmd="aws cloudformation create-stack"
    aws_cmd="$aws_cmd --stack-name $stack_name"
    aws_cmd="$aws_cmd --template-body file://$template_path"
    aws_cmd="$aws_cmd --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM"
    aws_cmd="$aws_cmd --region us-east-1"
    
    # 添加参数
    if [ ${#parameters[@]} -gt 0 ]; then
        aws_cmd="$aws_cmd --parameters"
        for param in "${parameters[@]}"; do
            aws_cmd="$aws_cmd $param"
        done
    fi
    
    # 添加标签
    aws_cmd="$aws_cmd --tags Key=Module,Value=$module Key=Version,Value=$version Key=Timestamp,Value=$(date +%s)"
    
    log_info "执行命令: $aws_cmd"
    
    # 执行部署
    eval $aws_cmd
    local deploy_result=$?
    
    if [ $deploy_result -eq 0 ]; then
        log_success "模块 $module 部署命令已提交"
        
        # 记录部署信息
        echo "$(date): 部署模块 $module 版本 $version 到栈 $stack_name" >> "$TEMPLATE_BASE_PATH/../deployment-history.log"
        
        return 0
    else
        log_error "模块 $module 部署失败"
        return $deploy_result
    fi
}

# 批量部署函数
deploy_all_modules() {
    local version=${1:-"current"}
    local payer_name=$2
    local timestamp=${3:-$(date +%s)}
    
    if [ -z "$payer_name" ]; then
        log_error "请指定Payer名称"
        log_info "使用方法: deploy_all_modules [version] <payer_name> [timestamp]"
        return 1
    fi
    
    log_info "开始批量部署所有模块 (版本: $version, Payer: $payer_name)"
    
    # 检查版本状态
    if [ "$version" != "current" ]; then
        check_version_status "$version" || {
            log_warning "使用非推荐版本进行部署"
            read -p "确认继续? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
        }
    fi
    
    # 定义部署顺序和参数
    local modules=(
        "02-billing-conductor"
        "03-cur-proforma"
        "04-cur-risp"
        "05-athena-setup"
        "06-account-auto-management"
        "07-cloudfront-monitoring"
    )
    
    local failed_modules=()
    
    for module in "${modules[@]}"; do
        local stack_name="payer-$payer_name-${module#*-}-$timestamp"
        
        log_info "部署模块: $module"
        
        # 根据模块设置特定参数
        local params=()
        case "$module" in
            "05-athena-setup")
                params=(
                    "ParameterKey=ProformaBucketName,ParameterValue=bip-cur-$MASTER_ACCOUNT_ID"
                    "ParameterKey=RISPBucketName,ParameterValue=bip-risp-cur-$MASTER_ACCOUNT_ID"
                    "ParameterKey=ProformaReportName,ParameterValue=$MASTER_ACCOUNT_ID"
                    "ParameterKey=RISPReportName,ParameterValue=risp-$MASTER_ACCOUNT_ID"
                )
                ;;
            "06-account-auto-management")
                if [ -n "$NORMAL_OU_ID" ]; then
                    params=("ParameterKey=NormalOUId,ParameterValue=$NORMAL_OU_ID")
                fi
                ;;
        esac
        
        if deploy_module_with_version "$module" "$version" "$stack_name" "${params[@]}"; then
            log_success "模块 $module 部署成功"
        else
            log_error "模块 $module 部署失败"
            failed_modules+=("$module")
        fi
        
        # 等待一段时间避免API限制
        sleep 5
    done
    
    # 输出结果摘要
    if [ ${#failed_modules[@]} -eq 0 ]; then
        log_success "所有模块部署完成!"
    else
        log_error "以下模块部署失败: ${failed_modules[*]}"
        return 1
    fi
}

# ==============================================================================
# 版本管理维护函数
# ==============================================================================

# 创建新版本
create_new_version() {
    local new_version=$1
    local description=$2
    local base_version=${3:-"current"}
    
    if [ -z "$new_version" ] || [ -z "$description" ]; then
        log_error "使用方法: create_new_version <new_version> <description> [base_version]"
        return 1
    fi
    
    # 检查版本是否已存在
    if jq -e ".versions.\"$new_version\"" "$VERSION_REGISTRY" >/dev/null 2>&1; then
        log_error "版本 $new_version 已存在"
        return 1
    fi
    
    log_info "创建新版本: $new_version (基于: $base_version)"
    
    # 创建版本目录
    local new_version_path="$TEMPLATE_BASE_PATH/versions/$new_version"
    mkdir -p "$new_version_path"
    
    # 复制基础版本的模板
    local base_path
    if [ "$base_version" = "current" ]; then
        base_path="$TEMPLATE_BASE_PATH/current"
    else
        base_path="$TEMPLATE_BASE_PATH/versions/$base_version"
    fi
    
    if [ ! -d "$base_path" ]; then
        log_error "基础版本路径不存在: $base_path"
        return 1
    fi
    
    cp -r "$base_path"/* "$new_version_path/"
    
    # 更新版本注册表
    local temp_registry=$(mktemp)
    jq ".versions.\"$new_version\" = {
        \"status\": \"beta\",
        \"description\": \"$description\",
        \"created\": \"$(date -Iseconds)\",
        \"modules\": {}
    }" "$VERSION_REGISTRY" > "$temp_registry"
    
    mv "$temp_registry" "$VERSION_REGISTRY"
    
    log_success "新版本 $new_version 创建完成"
}

# 更新current指向
update_current_version() {
    local target_version=$1
    
    if [ -z "$target_version" ]; then
        log_error "请指定目标版本"
        return 1
    fi
    
    # 检查目标版本是否存在
    if ! jq -e ".versions.\"$target_version\"" "$VERSION_REGISTRY" >/dev/null 2>&1; then
        log_error "版本 $target_version 不存在"
        return 1
    fi
    
    log_info "将current版本指向: $target_version"
    
    # 删除旧的符号链接
    rm -rf "$TEMPLATE_BASE_PATH/current"
    
    # 创建新的符号链接
    mkdir -p "$TEMPLATE_BASE_PATH/current"
    for module_dir in "$TEMPLATE_BASE_PATH/versions/$target_version"/*; do
        if [ -d "$module_dir" ]; then
            local module_name=$(basename "$module_dir")
            ln -sf "../versions/$target_version/$module_name" "$TEMPLATE_BASE_PATH/current/$module_name"
        fi
    done
    
    # 更新注册表
    local temp_registry=$(mktemp)
    jq ".current_version = \"$target_version\"" "$VERSION_REGISTRY" > "$temp_registry"
    mv "$temp_registry" "$VERSION_REGISTRY"
    
    log_success "current版本已更新为: $target_version"
}

# ==============================================================================
# 主函数和命令行接口
# ==============================================================================

# 显示帮助信息
show_help() {
    cat << EOF
Payer模板版本管理脚本

使用方法:
  $0 <命令> [选项]

命令:
  list-versions                           列出所有可用版本
  version-info <version>                  显示指定版本的详细信息
  deploy <module> <version> <stack_name>  部署指定模块和版本
  deploy-all <version> <payer_name>       批量部署所有模块
  create-version <version> <description>  创建新版本
  update-current <version>                更新current指向
  template-path <version> <module>        获取模板路径
  help                                    显示此帮助信息

示例:
  $0 list-versions
  $0 version-info v1
  $0 deploy 05-athena-setup v1 payer-test-athena-123456
  $0 deploy-all v1 test-payer
  $0 template-path current 05-athena-setup

环境变量:
  MASTER_ACCOUNT_ID   主账户ID（Athena模块需要）
  NORMAL_OU_ID        正常OU ID（账户管理模块需要）

EOF
}

# 主函数
main() {
    local command=$1
    
    case "$command" in
        "list-versions"|"list")
            list_versions
            ;;
        "version-info"|"info")
            get_version_info "$2"
            ;;
        "deploy")
            deploy_module_with_version "$2" "$3" "$4" "${@:5}"
            ;;
        "deploy-all")
            deploy_all_modules "$2" "$3" "$4"
            ;;
        "create-version"|"create")
            create_new_version "$2" "$3" "$4"
            ;;
        "update-current"|"update")
            update_current_version "$2"
            ;;
        "template-path"|"path")
            get_template_path "$2" "$3" "$4"
            ;;
        "help"|"-h"|"--help"|"")
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi