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
    echo "      Parameters: --normal-ou-id <ou_id> [--use-existing-cloudtrail] [--existing-cloudtrail-name <name>]"
    echo ""
    echo "Examples:"
    echo "  $0 1 --root-id r-abcd1234"
    echo "  $0 2"
    echo "  $0 3 --billing-group-arn arn:aws:billingconductor::123456789012:billinggroup/12345678"
    echo "  $0 4"
    echo "  $0 5 --proforma-bucket bip-cur-123456789012 --risp-bucket bip-risp-cur-123456789012 --proforma-report 123456789012 --risp-report risp-123456789012"
    echo "  $0 6 --normal-ou-id ou-abcd-12345678"
    echo "  $0 6 --normal-ou-id ou-abcd-12345678 --use-existing-cloudtrail --existing-cloudtrail-name my-existing-trail"
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
    local use_existing_cloudtrail=$2
    local existing_cloudtrail_name=$3
    
    if [ -z "$normal_ou_id" ]; then
        print_error "Normal OU ID is required for Module 6"
        print_status "You can get it from Module 1 stack outputs:"
        print_status "aws cloudformation describe-stacks --stack-name payer-ou-scp-* --query 'Stacks[0].Outputs[?OutputKey==\`NormalOUId\`].OutputValue' --output text"
        exit 1
    fi
    
    print_status "Deploying Module 6: Account Auto Movement"
    print_status "Normal OU ID: $normal_ou_id"
    
    local stack_name="${STACK_PREFIX}-account-auto-move-${TIMESTAMP}"
    local parameters="ParameterKey=NormalOUId,ParameterValue=$normal_ou_id"
    
    if [ "$use_existing_cloudtrail" = "true" ]; then
        if [ -z "$existing_cloudtrail_name" ]; then
            print_error "Existing CloudTrail name is required when using existing CloudTrail"
            exit 1
        fi
        print_status "Using existing CloudTrail: $existing_cloudtrail_name"
        parameters="$parameters ParameterKey=UseExistingCloudTrail,ParameterValue=true"
        parameters="$parameters ParameterKey=ExistingCloudTrailName,ParameterValue=$existing_cloudtrail_name"
    else
        print_status "Will create new CloudTrail for Organizations events"
        parameters="$parameters ParameterKey=UseExistingCloudTrail,ParameterValue=false"
    fi
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/06-account-auto-management/account_auto_move.yaml \
        --parameters $parameters \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    # Get CloudTrail status for reference
    local cloudtrail_status=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailStatus`].OutputValue' --output text)
    
    print_success "Module 6 deployed successfully: $stack_name"
    print_status "CloudTrail Status: $cloudtrail_status"
    print_warning "Account auto-movement is now active - new accounts will be automatically moved to Normal OU"
    
    if [ "$use_existing_cloudtrail" = "true" ]; then
        print_status "Using existing CloudTrail: $existing_cloudtrail_name"
        print_status "Make sure the existing CloudTrail is configured to capture Organizations management events"
    else
        local cloudtrail_bucket=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[0].Outputs[?OutputKey==`CloudTrailBucketName`].OutputValue' --output text)
        print_status "CloudTrail Bucket: $cloudtrail_bucket"
        print_status "Monitor CloudTrail logs in the bucket for account movement activities"
    fi
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
            USE_EXISTING_CLOUDTRAIL="false"
            EXISTING_CLOUDTRAIL_NAME=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --normal-ou-id)
                        NORMAL_OU_ID="$2"
                        shift 2
                        ;;
                    --use-existing-cloudtrail)
                        USE_EXISTING_CLOUDTRAIL="true"
                        shift
                        ;;
                    --existing-cloudtrail-name)
                        EXISTING_CLOUDTRAIL_NAME="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Unknown parameter: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            deploy_module6 "$NORMAL_OU_ID" "$USE_EXISTING_CLOUDTRAIL" "$EXISTING_CLOUDTRAIL_NAME"
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