#!/bin/bash

# AWS Payer Automation - Single Module Deployment Script
# This script deploys a single module with proper parameter handling

set -e

# Configuration
TIMESTAMP=$(date +%s)
REGION="us-east-1"  # CUR requires us-east-1
STACK_PREFIX="payer"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <module_number> [parameters]"
    echo ""
    echo "Modules:"
    echo "  1 - OU and SCP Setup"
    echo "      Parameters: --root-id <root_id>"
    echo "  2 - BillingConductor Setup"
    echo "      Parameters: none"
    echo "  3 - Pro forma CUR Export"
    echo "      Parameters: --billing-group-arn <arn>"
    echo "  4 - RISP CUR Export"
    echo "      Parameters: none"
    echo "  5 - Athena Setup"
    echo "      Parameters: --proforma-bucket <bucket> --risp-bucket <bucket> --proforma-report <name> --risp-report <name>"
    echo "  6 - Account Auto Movement"
    echo "      Parameters: --normal-ou-id <ou_id> [--cloudtrail-mode auto|true|false]"
    echo "  7 - CloudFront Monitoring"
    echo "      Parameters: --payer-name <name> --member-accounts <account1,account2> [--threshold-mb <number>] [--telegram-group-id <id>]"
    echo ""
    echo "Examples:"
    echo "  $0 1 --root-id r-abcd1234"
    echo "  $0 2"
    echo "  $0 3 --billing-group-arn arn:aws:billingconductor::123456789012:billinggroup/12345678"
    echo "  $0 4"
    echo "  $0 5 --proforma-bucket bip-cur-123456789012 --risp-bucket bip-risp-cur-123456789012 --proforma-report 123456789012 --risp-report risp-123456789012"
    echo "  $0 6 --normal-ou-id ou-abcd-12345678"
    echo "  $0 6 --normal-ou-id ou-abcd-12345678 --cloudtrail-mode auto"
    echo "  $0 6 --normal-ou-id ou-abcd-12345678 --cloudtrail-mode true"
    echo "  $0 6 --normal-ou-id ou-abcd-12345678 --cloudtrail-mode false"
    echo "  $0 7 --payer-name EliteSPP --member-accounts 123456789012,234567890123"
    echo "  $0 7 --payer-name EliteSPP --member-accounts 123456789012,234567890123 --threshold-mb 150"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    print_success "AWS CLI is configured"
}

# Function to wait for stack completion
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    
    print_status "Waiting for $operation to complete for stack: $stack_name"
    
    if [ "$operation" = "create" ]; then
        aws cloudformation wait stack-create-complete --stack-name "$stack_name" --region "$REGION"
    elif [ "$operation" = "update" ]; then
        aws cloudformation wait stack-update-complete --stack-name "$stack_name" --region "$REGION"
    fi
    
    local status=$?
    if [ $status -eq 0 ]; then
        print_success "Stack $stack_name $operation completed successfully"
    else
        print_error "Stack $stack_name $operation failed"
        # Show stack events for debugging
        print_status "Stack events:"
        aws cloudformation describe-stack-events --stack-name "$stack_name" --region "$REGION" --max-items 10
        exit 1
    fi
}

# Function to deploy module 1
deploy_module1() {
    local root_id=$1
    
    if [ -z "$root_id" ]; then
        print_error "Root ID is required for Module 1"
        print_status "You can get it with: aws organizations list-roots --query 'Roots[0].Id' --output text"
        exit 1
    fi
    
    print_status "Deploying Module 1: OU and SCP Setup"
    print_status "Root ID: $root_id"
    
    local stack_name="${STACK_PREFIX}-ou-scp-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/01-ou-scp/auto_SCP_1.yaml \
        --parameters ParameterKey=RootId,ParameterValue="$root_id" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    print_success "Module 1 deployed successfully: $stack_name"
}

# Function to deploy module 2
deploy_module2() {
    print_status "Deploying Module 2: BillingConductor Setup"
    
    local stack_name="${STACK_PREFIX}-billing-conductor-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/02-billing-conductor/billing_conductor.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    # Get BillingGroup ARN for reference
    local billing_group_arn=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='BillingGroupArn'].OutputValue" \
        --output text)
    
    print_success "Module 2 deployed successfully: $stack_name"
    print_status "BillingGroup ARN: $billing_group_arn"
    print_status "Use this ARN for Module 3 deployment"
}

# Function to deploy module 3
deploy_module3() {
    local billing_group_arn=$1
    
    if [ -z "$billing_group_arn" ]; then
        print_error "BillingGroup ARN is required for Module 3"
        print_status "You can get it from Module 2 stack outputs or use:"
        print_status "aws cloudformation describe-stacks --stack-name <module2-stack-name> --query 'Stacks[0].Outputs[?OutputKey==\`BillingGroupArn\`].OutputValue' --output text"
        exit 1
    fi
    
    print_status "Deploying Module 3: Pro forma CUR Export"
    print_status "BillingGroup ARN: $billing_group_arn"
    
    local stack_name="${STACK_PREFIX}-cur-proforma-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/03-cur-proforma/cur_export_proforma.yaml \
        --parameters ParameterKey=BillingGroupArn,ParameterValue="$billing_group_arn" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    print_success "Module 3 deployed successfully: $stack_name"
    print_warning "CUR reports may take up to 24 hours to generate first data"
}

# Function to deploy module 4
deploy_module4() {
    print_status "Deploying Module 4: RISP CUR Export"
    
    local stack_name="${STACK_PREFIX}-cur-risp-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/04-cur-risp/cur_export_risp.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    print_success "Module 4 deployed successfully: $stack_name"
    print_warning "CUR reports may take up to 24 hours to generate first data"
}

# Function to deploy module 5
deploy_module5() {
    local proforma_bucket=$1
    local risp_bucket=$2
    local proforma_report=$3
    local risp_report=$4
    
    if [ -z "$proforma_bucket" ] || [ -z "$risp_bucket" ] || [ -z "$proforma_report" ] || [ -z "$risp_report" ]; then
        print_error "All parameters are required for Module 5"
        print_status "Required: --proforma-bucket, --risp-bucket, --proforma-report, --risp-report"
        print_status "You can get these from Module 3 and 4 stack outputs:"
        print_status "aws cloudformation describe-stacks --stack-name payer-cur-proforma-* --query 'Stacks[0].Outputs'"
        print_status "aws cloudformation describe-stacks --stack-name payer-cur-risp-* --query 'Stacks[0].Outputs'"
        exit 1
    fi
    
    print_status "Deploying Module 5: Athena Setup"
    print_status "Pro forma Bucket: $proforma_bucket"
    print_status "RISP Bucket: $risp_bucket"
    print_status "Pro forma Report: $proforma_report"
    print_status "RISP Report: $risp_report"
    
    local stack_name="${STACK_PREFIX}-athena-setup-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/05-athena-setup/athena_setup.yaml \
        --parameters \
            ParameterKey=ProformaBucketName,ParameterValue="$proforma_bucket" \
            ParameterKey=RISPBucketName,ParameterValue="$risp_bucket" \
            ParameterKey=ProformaReportName,ParameterValue="$proforma_report" \
            ParameterKey=RISPReportName,ParameterValue="$risp_report" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    # Get database name for reference
    local database_name=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`DatabaseName`].OutputValue' --output text)
    
    print_success "Module 5 deployed successfully: $stack_name"
    print_status "Athena Database: $database_name"
    print_warning "Athena crawlers will start automatically but may take 10-15 minutes to complete"
    print_status "Use this database name for querying CUR data in Athena"
}

# Function to deploy module 6
deploy_module6() {
    local normal_ou_id=$1
    local cloudtrail_mode=$2
    
    if [ -z "$normal_ou_id" ]; then
        print_error "Normal OU ID is required for Module 6"
        print_status "You can get it from Module 1 stack outputs:"
        print_status "aws cloudformation describe-stacks --stack-name payer-ou-scp-* --query 'Stacks[0].Outputs[?OutputKey==\`NormalOUId\`].OutputValue' --output text"
        exit 1
    fi
    
    # Default to auto mode if not specified
    if [ -z "$cloudtrail_mode" ]; then
        cloudtrail_mode="auto"
    fi
    
    print_status "Deploying Module 6: Account Auto Movement"
    print_status "Normal OU ID: $normal_ou_id"
    print_status "CloudTrail Mode: $cloudtrail_mode"
    
    local stack_name="${STACK_PREFIX}-account-auto-move-${TIMESTAMP}"
    local parameters="ParameterKey=NormalOUId,ParameterValue=$normal_ou_id"
    parameters="$parameters ParameterKey=CreateCloudTrail,ParameterValue=$cloudtrail_mode"
    
    case $cloudtrail_mode in
        "auto")
            print_status "Auto mode: Will detect existing CloudTrail and create if needed"
            ;;
        "true")
            print_status "Force mode: Will create new CloudTrail for Organizations events"
            ;;
        "false")
            print_status "Skip mode: Will not create CloudTrail (assumes existing infrastructure)"
            ;;
    esac
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/06-account-auto-management/account_auto_move.yaml \
        --parameters $parameters \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    # Get deployment results
    local cloudtrail_status=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailStatus`].OutputValue' --output text)
    local management_result=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailManagementResult`].OutputValue' --output text)
    local cloudtrail_bucket=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailBucketName`].OutputValue' --output text)
    local cloudtrail_name=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailName`].OutputValue' --output text)
    
    print_success "Module 6 deployed successfully: $stack_name"
    print_status "CloudTrail Status: $cloudtrail_status"
    print_status "CloudTrail Name: $cloudtrail_name"
    
    if [ "$cloudtrail_mode" = "auto" ]; then
        print_status "Management Results:"
        echo "$management_result" | while IFS= read -r line; do
            print_status "  $line"
        done
    fi
    
    print_warning "Account auto-movement is now active - new accounts will be automatically moved to Normal OU"
    
    # Show CloudTrail bucket info
    if [ "$cloudtrail_bucket" != "None" ] && [ -n "$cloudtrail_bucket" ]; then
        print_status "CloudTrail Bucket: $cloudtrail_bucket"
        print_status "Monitor CloudTrail logs in the bucket for account movement activities"
    fi
}

# Function to deploy module 7
deploy_module7() {
    local payer_name=$1
    local member_accounts=$2
    local threshold_mb=$3
    local telegram_group_id=$4
    
    if [ -z "$payer_name" ]; then
        print_error "Payer name is required for Module 7"
        print_status "Example: ./scripts/deploy-single.sh 7 --payer-name EliteSPP --member-accounts 123456789012,234567890123"
        exit 1
    fi
    
    if [ -z "$member_accounts" ]; then
        print_error "Member account IDs are required for Module 7"
        print_status "Example: --member-accounts 123456789012,234567890123,345678901234"
        exit 1
    fi
    
    # Default values
    if [ -z "$threshold_mb" ]; then
        threshold_mb="100"
    fi
    
    if [ -z "$telegram_group_id" ]; then
        telegram_group_id="-862835857"
    fi
    
    print_status "Deploying Module 7: CloudFront Monitoring"
    print_status "Payer Name: $payer_name"
    print_status "Member Accounts: $member_accounts"
    print_status "Threshold: $threshold_mb MB"
    print_status "Telegram Group: $telegram_group_id"
    
    local stack_name="${STACK_PREFIX}-cloudfront-monitoring-${TIMESTAMP}"
    
    # Validate member accounts format
    if ! echo "$member_accounts" | grep -qE '^[0-9,]+$'; then
        print_error "Member accounts must be comma-separated account IDs (numbers only)"
        exit 1
    fi
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml \
        --parameters \
            ParameterKey=PayerName,ParameterValue="$payer_name" \
            ParameterKey=MemberAccountIds,ParameterValue="$member_accounts" \
            ParameterKey=CloudFrontThresholdMB,ParameterValue="$threshold_mb" \
            ParameterKey=TelegramGroupId,ParameterValue="$telegram_group_id" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    # Get deployment results
    local monitoring_sink=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`MonitoringSinkArn`].OutputValue' --output text)
    local alarm_name=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontAlarmName`].OutputValue' --output text)
    local alert_function=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`AlertFunctionArn`].OutputValue' --output text)
    
    print_success "Module 7 deployed successfully: $stack_name"
    print_status "OAM Sink ARN: $monitoring_sink"
    print_status "CloudWatch Alarm: $alarm_name"
    print_status "Alert Function: $alert_function"
    
    print_warning "CloudFront monitoring is now active with ${threshold_mb}MB threshold"
    print_status "Member accounts: $(echo $member_accounts | tr ',' ' ')"
    
    # Show setup results
    print_status ""
    print_status "Next steps:"
    print_status "1. Verify OAM Links are created in member accounts"
    print_status "2. Test CloudFront traffic monitoring"
    print_status "3. Monitor Telegram notifications"
    print_status ""
    print_status "Monitor CloudWatch Logs:"
    print_status "  - OAM Setup: /aws/lambda/${payer_name}-OAM-Setup"
    print_status "  - Alerts: /aws/lambda/${payer_name}-CloudFront-Alert"
}

# Main function
main() {
    if [ $# -lt 1 ]; then
        show_usage
        exit 1
    fi
    
    local module=$1
    shift
    
    # Check current directory
    if [ ! -d "templates" ]; then
        print_error "Please run this script from the aws-payer-automation directory"
        exit 1
    fi
    
    check_aws_cli
    
    print_status "Starting single module deployment"
    print_status "Module: $module"
    print_status "Timestamp: $TIMESTAMP"
    
    case $module in
        1)
            # Parse parameters for module 1
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --root-id)
                        ROOT_ID="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Unknown parameter: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            deploy_module1 "$ROOT_ID"
            ;;
        2)
            deploy_module2
            ;;
        3)
            # Parse parameters for module 3
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --billing-group-arn)
                        BILLING_GROUP_ARN="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Unknown parameter: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            deploy_module3 "$BILLING_GROUP_ARN"
            ;;
        4)
            deploy_module4
            ;;
        5)
            # Parse parameters for module 5
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --proforma-bucket)
                        PROFORMA_BUCKET="$2"
                        shift 2
                        ;;
                    --risp-bucket)
                        RISP_BUCKET="$2"
                        shift 2
                        ;;
                    --proforma-report)
                        PROFORMA_REPORT="$2"
                        shift 2
                        ;;
                    --risp-report)
                        RISP_REPORT="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Unknown parameter: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            deploy_module5 "$PROFORMA_BUCKET" "$RISP_BUCKET" "$PROFORMA_REPORT" "$RISP_REPORT"
            ;;
        6)
            # Parse parameters for module 6
            CLOUDTRAIL_MODE="auto"
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --normal-ou-id)
                        NORMAL_OU_ID="$2"
                        shift 2
                        ;;
                    --cloudtrail-mode)
                        CLOUDTRAIL_MODE="$2"
                        if [[ ! "$CLOUDTRAIL_MODE" =~ ^(auto|true|false)$ ]]; then
                            print_error "Invalid cloudtrail-mode: $CLOUDTRAIL_MODE. Must be auto, true, or false"
                            exit 1
                        fi
                        shift 2
                        ;;
                    # Legacy support for --create-cloudtrail
                    --create-cloudtrail)
                        CLOUDTRAIL_MODE="true"
                        shift
                        ;;
                    *)
                        print_error "Unknown parameter: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            deploy_module6 "$NORMAL_OU_ID" "$CLOUDTRAIL_MODE"
            ;;
        7)
            # Parse parameters for module 7
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --payer-name)
                        PAYER_NAME="$2"
                        shift 2
                        ;;
                    --member-accounts)
                        MEMBER_ACCOUNTS="$2"
                        shift 2
                        ;;
                    --threshold-mb)
                        THRESHOLD_MB="$2"
                        shift 2
                        ;;
                    --telegram-group-id)
                        TELEGRAM_GROUP_ID="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Unknown parameter: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            deploy_module7 "$PAYER_NAME" "$MEMBER_ACCOUNTS" "$THRESHOLD_MB" "$TELEGRAM_GROUP_ID"
            ;;
        *)
            print_error "Invalid module number: $module"
            show_usage
            exit 1
            ;;
    esac
}

# Handle script interruption
trap 'print_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"