#!/bin/bash

# AWS Payer Automation - Cleanup Script
# This script helps cleanup deployed stacks (use with caution)

set -e

# Configuration
REGION="us-east-1"
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
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --list                 List all payer-related stacks"
    echo "  --delete-all           Delete all payer-related stacks (DANGEROUS)"
    echo "  --delete-stack <name>  Delete a specific stack"
    echo "  --dry-run             Show what would be deleted without actually deleting"
    echo "  --force               Skip confirmation prompts"
    echo ""
    echo "Examples:"
    echo "  $0 --list"
    echo "  $0 --delete-stack payer-ou-scp-1234567890"
    echo "  $0 --delete-all --dry-run"
    echo "  $0 --delete-all --force"
    echo ""
    echo "WARNING: This script can delete resources permanently!"
    echo "Make sure you understand what you're deleting before proceeding."
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
}

# Function to list all payer stacks
list_stacks() {
    print_status "Listing all payer-related stacks..."
    
    local stacks=$(aws cloudformation list-stacks \
        --region "$REGION" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?starts_with(StackName, '$STACK_PREFIX-')].{Name:StackName,Status:StackStatus,Created:CreationTime}" \
        --output table)
    
    if [ -n "$stacks" ]; then
        echo "$stacks"
    else
        print_status "No payer-related stacks found"
    fi
}

# Function to get stack resources
get_stack_resources() {
    local stack_name=$1
    
    print_status "Resources in stack $stack_name:"
    
    aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "StackResourceSummaries[].{Type:ResourceType,LogicalId:LogicalResourceId,Status:ResourceStatus}" \
        --output table
}

# Function to check for protected resources
check_protected_resources() {
    local stack_name=$1
    
    print_status "Checking for protected resources in $stack_name..."
    
    # Check for S3 buckets
    local s3_buckets=$(aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
        --output text)
    
    if [ -n "$s3_buckets" ]; then
        print_warning "Stack contains S3 buckets that may contain data:"
        for bucket in $s3_buckets; do
            echo "  - $bucket"
        done
    fi
    
    # Check for billing-related resources
    local billing_resources=$(aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "StackResourceSummaries[?contains(ResourceType, 'BillingConductor') || contains(ResourceType, 'CUR')].{Type:ResourceType,Id:LogicalResourceId}" \
        --output text)
    
    if [ -n "$billing_resources" ]; then
        print_warning "Stack contains billing-related resources:"
        echo "$billing_resources"
    fi
    
    # Check for Glue and Lambda resources (Module 5)
    local athena_resources=$(aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "StackResourceSummaries[?contains(ResourceType, 'Glue') || contains(ResourceType, 'Lambda')].{Type:ResourceType,Id:LogicalResourceId}" \
        --output text)
    
    if [ -n "$athena_resources" ]; then
        print_warning "Stack contains Athena/Glue resources:"
        echo "$athena_resources"
        print_warning "Note: Glue databases and tables contain data that will be lost"
    fi
}

# Function to wait for stack deletion
wait_for_deletion() {
    local stack_name=$1
    
    print_status "Waiting for stack deletion: $stack_name"
    
    aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$REGION"
    
    local status=$?
    if [ $status -eq 0 ]; then
        print_success "Stack $stack_name deleted successfully"
    else
        print_error "Stack $stack_name deletion failed"
        # Show stack events for debugging
        print_status "Recent stack events:"
        aws cloudformation describe-stack-events --stack-name "$stack_name" --region "$REGION" --max-items 10 2>/dev/null || true
    fi
}

# Function to delete a specific stack
delete_stack() {
    local stack_name=$1
    local dry_run=$2
    local force=$3
    
    print_status "Preparing to delete stack: $stack_name"
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &> /dev/null; then
        print_error "Stack $stack_name does not exist"
        return 1
    fi
    
    # Show stack resources
    get_stack_resources "$stack_name"
    
    # Check for protected resources
    check_protected_resources "$stack_name"
    
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN: Would delete stack $stack_name"
        return 0
    fi
    
    # Confirmation
    if [ "$force" != "true" ]; then
        echo ""
        print_warning "This will permanently delete the stack and all its resources!"
        read -p "Are you sure you want to delete stack $stack_name? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            print_status "Deletion cancelled"
            return 0
        fi
    fi
    
    # Delete the stack
    print_status "Deleting stack: $stack_name"
    aws cloudformation delete-stack --stack-name "$stack_name" --region "$REGION"
    
    wait_for_deletion "$stack_name"
}

# Function to delete all payer stacks
delete_all_stacks() {
    local dry_run=$1
    local force=$2
    
    print_status "Finding all payer-related stacks..."
    
    local stack_names=$(aws cloudformation list-stacks \
        --region "$REGION" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?starts_with(StackName, '$STACK_PREFIX-')].StackName" \
        --output text)
    
    if [ -z "$stack_names" ]; then
        print_status "No payer-related stacks found"
        return 0
    fi
    
    print_status "Found stacks to delete:"
    for stack in $stack_names; do
        echo "  - $stack"
    done
    
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN: Would delete all listed stacks"
        return 0
    fi
    
    # Confirmation for all stacks
    if [ "$force" != "true" ]; then
        echo ""
        print_warning "This will permanently delete ALL payer-related stacks and their resources!"
        read -p "Are you absolutely sure? Type 'DELETE ALL' to confirm: " confirm
        
        if [ "$confirm" != "DELETE ALL" ]; then
            print_status "Deletion cancelled"
            return 0
        fi
    fi
    
    # Delete stacks in reverse order (to handle dependencies)
    local stack_array=($stack_names)
    for (( i=${#stack_array[@]}-1 ; i>=0 ; i-- )); do
        delete_stack "${stack_array[i]}" "false" "true"
    done
    
    print_success "All stacks deleted"
}

# Main function
main() {
    local list_only=false
    local delete_all=false
    local delete_stack_name=""
    local dry_run=false
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                list_only=true
                shift
                ;;
            --delete-all)
                delete_all=true
                shift
                ;;
            --delete-stack)
                delete_stack_name="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate arguments
    if [ "$list_only" = "false" ] && [ "$delete_all" = "false" ] && [ -z "$delete_stack_name" ]; then
        show_usage
        exit 1
    fi
    
    check_aws_cli
    
    if [ "$list_only" = "true" ]; then
        list_stacks
    elif [ "$delete_all" = "true" ]; then
        delete_all_stacks "$dry_run" "$force"
    elif [ -n "$delete_stack_name" ]; then
        delete_stack "$delete_stack_name" "$dry_run" "$force"
    fi
}

# Handle script interruption
trap 'print_error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"