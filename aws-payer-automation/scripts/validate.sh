#!/bin/bash

# AWS Payer Automation - Template Validation Script
# This script validates all CloudFormation templates

set -e

# Configuration
REGION="us-east-1"

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

# Function to validate a template
validate_template() {
    local template_path=$1
    local template_name=$2
    
    print_status "Validating $template_name..."
    
    if [ ! -f "$template_path" ]; then
        print_error "Template file not found: $template_path"
        return 1
    fi
    
    local validation_result
    if validation_result=$(aws cloudformation validate-template --template-body file://"$template_path" --region "$REGION" 2>&1); then
        print_success "$template_name validation passed"
        
        # Extract and display template parameters
        local parameters=$(echo "$validation_result" | jq -r '.Parameters[]? | "  - \(.ParameterKey): \(.Description // "No description")"' 2>/dev/null || echo "  No parameters")
        if [ "$parameters" != "  No parameters" ]; then
            print_status "Parameters for $template_name:"
            echo "$parameters"
        fi
        
        return 0
    else
        print_error "$template_name validation failed"
        echo "$validation_result"
        return 1
    fi
}

# Function to check template syntax
check_yaml_syntax() {
    local template_path=$1
    local template_name=$2
    
    print_status "Checking YAML syntax for $template_name..."
    
    if command -v yamllint &> /dev/null; then
        if yamllint "$template_path" 2>/dev/null; then
            print_success "$template_name YAML syntax is valid"
        else
            print_warning "$template_name has YAML syntax issues (non-critical)"
        fi
    else
        print_warning "yamllint not installed, skipping YAML syntax check"
    fi
}

# Function to check for common CloudFormation issues
check_common_issues() {
    local template_path=$1
    local template_name=$2
    
    print_status "Checking common issues for $template_name..."
    
    # Check for hardcoded values that should be parameters
    if grep -q "123456789012" "$template_path"; then
        print_warning "$template_name contains hardcoded account ID"
    fi
    
    # Check for missing DeletionPolicy
    if grep -q "AWS::S3::Bucket" "$template_path" && ! grep -q "DeletionPolicy" "$template_path"; then
        print_warning "$template_name contains S3 buckets without DeletionPolicy"
    fi
    
    # Check for IAM roles with overly broad permissions
    if grep -q '"Resource": "\*"' "$template_path"; then
        print_warning "$template_name contains IAM permissions with wildcard resources"
    fi
    
    print_success "$template_name common issues check completed"
}

# Function to validate all templates
validate_all_templates() {
    local templates=(
        "templates/01-ou-scp/auto_SCP_1.yaml:Module 1 - OU and SCP"
        "templates/02-billing-conductor/billing_conductor.yaml:Module 2 - BillingConductor"
        "templates/03-cur-proforma/cur_export_proforma.yaml:Module 3 - Pro forma CUR"
        "templates/04-cur-risp/cur_export_risp.yaml:Module 4 - RISP CUR"
        "templates/05-athena-setup/athena_setup.yaml:Module 5 - Athena Setup"
    )
    
    local validation_count=0
    local success_count=0
    
    for template_info in "${templates[@]}"; do
        IFS=':' read -r template_path template_name <<< "$template_info"
        
        echo ""
        print_status "=== Validating $template_name ==="
        
        validation_count=$((validation_count + 1))
        
        # Check YAML syntax
        check_yaml_syntax "$template_path" "$template_name"
        
        # Validate template with AWS
        if validate_template "$template_path" "$template_name"; then
            success_count=$((success_count + 1))
        fi
        
        # Check for common issues
        check_common_issues "$template_path" "$template_name"
    done
    
    echo ""
    print_status "=== Validation Summary ==="
    echo "Total templates: $validation_count"
    echo "Successful validations: $success_count"
    echo "Failed validations: $((validation_count - success_count))"
    
    if [ $success_count -eq $validation_count ]; then
        print_success "All templates are valid!"
        return 0
    else
        print_error "Some templates failed validation"
        return 1
    fi
}

# Function to validate dependencies
validate_dependencies() {
    print_status "Checking template dependencies..."
    
    # Check if Module 3 references Module 2 output correctly
    if grep -q "BillingGroupArn" templates/03-cur-proforma/cur_export_proforma.yaml; then
        print_success "Module 3 correctly references BillingGroup parameter"
    else
        print_error "Module 3 missing BillingGroup parameter reference"
    fi
    
    # Check if Module 5 references CUR modules correctly
    if grep -q "ProformaBucketName\|RISPBucketName" templates/05-athena-setup/athena_setup.yaml; then
        print_success "Module 5 correctly references CUR parameters"
    else
        print_error "Module 5 missing CUR parameter references"
    fi
    
    # Check if templates exist
    local required_files=(
        "templates/01-ou-scp/auto_SCP_1.yaml"
        "templates/02-billing-conductor/billing_conductor.yaml"
        "templates/03-cur-proforma/cur_export_proforma.yaml"
        "templates/04-cur-risp/cur_export_risp.yaml"
        "templates/05-athena-setup/athena_setup.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            print_success "Required file exists: $file"
        else
            print_error "Missing required file: $file"
        fi
    done
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if user has necessary permissions
    if aws iam get-account-summary &> /dev/null; then
        print_success "IAM permissions check passed"
    else
        print_warning "Cannot verify IAM permissions"
    fi
    
    # Check if Organizations is accessible
    if aws organizations describe-organization &> /dev/null; then
        print_success "AWS Organizations is accessible"
    else
        print_warning "AWS Organizations not accessible (may be expected)"
    fi
    
    # Check if BillingConductor is available
    if aws billingconductor list-billing-groups --region us-east-1 &> /dev/null; then
        print_success "BillingConductor is accessible"
    else
        print_warning "BillingConductor not accessible (may be expected)"
    fi
}

# Main function
main() {
    print_status "Starting AWS Payer Automation Template Validation"
    
    # Check current directory
    if [ ! -d "templates" ]; then
        print_error "Please run this script from the aws-payer-automation directory"
        exit 1
    fi
    
    check_aws_cli
    check_prerequisites
    validate_dependencies
    
    if validate_all_templates; then
        print_success "All validations passed! Templates are ready for deployment."
        exit 0
    else
        print_error "Validation failed. Please fix the issues before deployment."
        exit 1
    fi
}

# Handle script interruption
trap 'print_error "Validation interrupted"; exit 1' INT TERM

# Run main function
main "$@"