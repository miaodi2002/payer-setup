#!/bin/bash

# AWS Payer Automation - Complete Deployment Script
# This script deploys all 7 modules in the correct order with dependency management

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS Organizations
    if ! aws organizations describe-organization &> /dev/null; then
        print_error "AWS Organizations is not enabled or accessible"
        exit 1
    fi
    
    # Get root ID
    ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
    if [ "$ROOT_ID" = "None" ]; then
        print_error "Could not retrieve Organizations root ID"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
    print_status "Root ID: $ROOT_ID"
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
        exit 1
    fi
}

# Function to get stack output
get_stack_output() {
    local stack_name=$1
    local output_key=$2
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text
}

# Function to deploy module 1 (OU and SCP)
deploy_module1() {
    print_status "Deploying Module 1: OU and SCP Setup"
    
    local stack_name="${STACK_PREFIX}-ou-scp-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/01-ou-scp/auto_SCP_1.yaml \
        --parameters ParameterKey=RootId,ParameterValue="$ROOT_ID" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    STACK1_NAME="$stack_name"
    print_success "Module 1 deployed successfully: $stack_name"
}

# Function to deploy module 2 (BillingConductor)
deploy_module2() {
    print_status "Deploying Module 2: BillingConductor Setup"
    
    local stack_name="${STACK_PREFIX}-billing-conductor-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/02-billing-conductor/billing_conductor.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    BILLING_GROUP_ARN=$(get_stack_output "$stack_name" "BillingGroupArn")
    STACK2_NAME="$stack_name"
    
    print_success "Module 2 deployed successfully: $stack_name"
    print_status "BillingGroup ARN: $BILLING_GROUP_ARN"
}

# Function to deploy module 3 (Pro forma CUR)
deploy_module3() {
    print_status "Deploying Module 3: Pro forma CUR Export"
    
    local stack_name="${STACK_PREFIX}-cur-proforma-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/03-cur-proforma/cur_export_proforma.yaml \
        --parameters ParameterKey=BillingGroupArn,ParameterValue="$BILLING_GROUP_ARN" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    STACK3_NAME="$stack_name"
    print_success "Module 3 deployed successfully: $stack_name"
}

# Function to deploy module 4 (RISP CUR)
deploy_module4() {
    print_status "Deploying Module 4: RISP CUR Export"
    
    local stack_name="${STACK_PREFIX}-cur-risp-${TIMESTAMP}"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/04-cur-risp/cur_export_risp.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    STACK4_NAME="$stack_name"
    print_success "Module 4 deployed successfully: $stack_name"
}

# Function to deploy module 5 (Athena Setup)
deploy_module5() {
    print_status "Deploying Module 5: Athena Setup"
    
    local stack_name="${STACK_PREFIX}-athena-setup-${TIMESTAMP}"
    
    # Get parameters from previous modules
    PROFORMA_BUCKET=$(get_stack_output "$STACK3_NAME" "BucketName")
    RISP_BUCKET=$(get_stack_output "$STACK4_NAME" "RISPBucketName")
    PROFORMA_REPORT=$(get_stack_output "$STACK3_NAME" "ReportName")
    RISP_REPORT=$(get_stack_output "$STACK4_NAME" "RISPReportName")
    
    print_status "Using parameters:"
    print_status "  Pro forma Bucket: $PROFORMA_BUCKET"
    print_status "  RISP Bucket: $RISP_BUCKET"
    print_status "  Pro forma Report: $PROFORMA_REPORT"
    print_status "  RISP Report: $RISP_REPORT"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/05-athena-setup/athena_setup.yaml \
        --parameters \
            ParameterKey=ProformaBucketName,ParameterValue="$PROFORMA_BUCKET" \
            ParameterKey=RISPBucketName,ParameterValue="$RISP_BUCKET" \
            ParameterKey=ProformaReportName,ParameterValue="$PROFORMA_REPORT" \
            ParameterKey=RISPReportName,ParameterValue="$RISP_REPORT" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    STACK5_NAME="$stack_name"
    DATABASE_NAME=$(get_stack_output "$stack_name" "DatabaseName")
    print_success "Module 5 deployed successfully: $stack_name"
    print_status "Athena Database: $DATABASE_NAME"
}

# Function to deploy module 6 (Account Auto Movement)
deploy_module6() {
    print_status "Deploying Module 6: Account Auto Movement"
    
    local stack_name="${STACK_PREFIX}-account-auto-move-${TIMESTAMP}"
    
    # Get Normal OU ID from Module 1
    NORMAL_OU_ID=$(get_stack_output "$STACK1_NAME" "NormalOUId")
    
    print_status "Using parameters:"
    print_status "  Normal OU ID: $NORMAL_OU_ID"
    
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/06-account-auto-management/account_auto_move.yaml \
        --parameters ParameterKey=NormalOUId,ParameterValue="$NORMAL_OU_ID" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    STACK6_NAME="$stack_name"
    CLOUDTRAIL_BUCKET=$(get_stack_output "$stack_name" "CloudTrailBucketName")
    print_success "Module 6 deployed successfully: $stack_name"
    print_status "CloudTrail Bucket: $CLOUDTRAIL_BUCKET"
}

# Function to enable CloudFormation StackSets trusted access
enable_stacksets_trusted_access() {
    print_status "Enabling CloudFormation StackSets trusted access with AWS Organizations"
    
    # Check if already enabled
    TRUSTED_ACCESS=$(aws organizations list-aws-service-access-for-organization \
        --query 'EnabledServicePrincipals[?ServicePrincipal==`member.org.stacksets.cloudformation.amazonaws.com`]' \
        --output text 2>/dev/null)
    
    if [ -z "$TRUSTED_ACCESS" ]; then
        aws organizations enable-aws-service-access \
            --service-principal member.org.stacksets.cloudformation.amazonaws.com
        print_success "CloudFormation StackSets trusted access enabled"
    else
        print_status "CloudFormation StackSets trusted access already enabled"
    fi
}

# Function to deploy module 7 (CloudFront Monitoring)
deploy_module7() {
    print_status "Deploying Module 7: CloudFront Monitoring"
    
    # Enable StackSets trusted access first
    enable_stacksets_trusted_access
    
    # Get Master Account name as Payer name
    MASTER_ACCOUNT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
    PAYER_NAME=$(aws organizations describe-account --account-id $MASTER_ACCOUNT_ID --query 'Account.Name' --output text)
    
    print_status "Using parameters:"
    print_status "  Master Account ID: $MASTER_ACCOUNT_ID"
    print_status "  Payer Name: $PAYER_NAME"
    
    local stack_name="${STACK_PREFIX}-cloudfront-monitoring-${TIMESTAMP}"
    
    # Deploy CloudFront monitoring infrastructure in Payer account
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml \
        --parameters \
            ParameterKey=PayerName,ParameterValue="$PAYER_NAME" \
            ParameterKey=CloudFrontThresholdMB,ParameterValue="100" \
            ParameterKey=TelegramGroupId,ParameterValue="-862835857" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    wait_for_stack "$stack_name" "create"
    
    STACK7_NAME="$stack_name"
    MONITORING_SINK_ARN=$(get_stack_output "$stack_name" "MonitoringSinkArn")
    
    print_success "Module 7 infrastructure deployed successfully: $stack_name"
    print_status "Monitoring Sink ARN: $MONITORING_SINK_ARN"
    
    # Create StackSet for OAM Links
    local stackset_name="${PAYER_NAME}-OAM-Links"
    
    print_status "Creating StackSet for OAM Links: $stackset_name"
    
    aws cloudformation create-stack-set \
        --stack-set-name "$stackset_name" \
        --template-body file://templates/07-cloudfront-monitoring/oam-link-stackset.yaml \
        --parameters \
            ParameterKey=OAMSinkArn,ParameterValue="$MONITORING_SINK_ARN" \
            ParameterKey=PayerName,ParameterValue="$PAYER_NAME" \
        --capabilities CAPABILITY_IAM \
        --permission-model SERVICE_MANAGED \
        --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
        --description "Deploy OAM Links for CloudFront monitoring across member accounts" \
        --region "$REGION"
    
    # Wait a moment for StackSet to be created
    sleep 10
    
    # Deploy StackSet to Normal OU
    NORMAL_OU_ID=$(get_stack_output "$STACK1_NAME" "NormalOUId")
    
    print_status "Deploying StackSet to Normal OU: $NORMAL_OU_ID"
    
    aws cloudformation create-stack-instances \
        --stack-set-name "$stackset_name" \
        --deployment-targets OrganizationalUnitIds="$NORMAL_OU_ID" \
        --regions "$REGION" \
        --region "$REGION"
    
    # Wait for StackSet deployment (this may take a while)
    print_status "Waiting for StackSet deployment to complete (this may take several minutes)"
    sleep 30  # Give it some time to start
    
    STACKSET_NAME="$stackset_name"
    print_success "Module 7 StackSet deployed successfully: $stackset_name"
}

# Function to print deployment summary
print_summary() {
    print_success "=== Deployment Summary ==="
    echo "Timestamp: $TIMESTAMP"
    echo "Region: $REGION"
    echo "Root ID: $ROOT_ID"
    echo "Payer Name: $PAYER_NAME"
    echo ""
    echo "Deployed Stacks:"
    echo "  1. OU and SCP: $STACK1_NAME"
    echo "  2. BillingConductor: $STACK2_NAME"
    echo "  3. Pro forma CUR: $STACK3_NAME"
    echo "  4. RISP CUR: $STACK4_NAME"
    echo "  5. Athena Setup: $STACK5_NAME"
    echo "  6. Account Auto Movement: $STACK6_NAME"
    echo "  7. CloudFront Monitoring: $STACK7_NAME"
    echo ""
    echo "Deployed StackSets:"
    echo "  - OAM Links: $STACKSET_NAME"
    echo ""
    echo "Key Resources:"
    echo "  BillingGroup ARN: $BILLING_GROUP_ARN"
    echo "  Normal OU ID: $NORMAL_OU_ID"
    echo "  Athena Database: $DATABASE_NAME"
    echo "  CloudTrail Bucket: $CLOUDTRAIL_BUCKET"
    echo "  Monitoring Sink ARN: $MONITORING_SINK_ARN"
    echo ""
    print_success "All 7 modules deployed successfully!"
    print_warning "Note: CUR reports may take up to 24 hours to generate first data"
    print_warning "Note: Athena crawlers will start automatically but may take 10-15 minutes to complete"
    print_warning "Note: Account auto-movement is now active - new accounts will be automatically moved to Normal OU"
    print_warning "Note: CloudFront monitoring is active with 100MB threshold - StackSet deployment to member accounts may take 10-15 minutes"
}

# Main deployment function
main() {
    print_status "Starting AWS Payer Automation Deployment"
    print_status "Timestamp: $TIMESTAMP"
    
    # Check current directory
    if [ ! -d "templates" ]; then
        print_error "Please run this script from the aws-payer-automation directory"
        exit 1
    fi
    
    check_aws_cli
    check_prerequisites
    
    # Deploy modules in order
    deploy_module1
    deploy_module2
    deploy_module3
    deploy_module4
    deploy_module5
    deploy_module6
    deploy_module7
    
    print_summary
}

# Handle script interruption
trap 'print_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"