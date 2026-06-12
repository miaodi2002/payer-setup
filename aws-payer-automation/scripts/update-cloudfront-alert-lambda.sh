#!/bin/bash

# AWS Payer Automation - CloudFront Alert Lambda Code Updater
# Updates ONLY the Lambda function code for an already-deployed Module 7 stack,
# without touching the CloudFormation stack itself.
#
# Use this to push the "top usage account" fix to existing Payers in place.
# NOTE: this bypasses CloudFormation. The template YAML must already carry the
# same code, otherwise the next `update-stack` will revert this change (drift).

set -e

REGION="us-east-1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    echo "Usage: $0 <PayerName>"
    echo ""
    echo "Updates the Lambda function '<PayerName>-CloudFront-Alert' with the"
    echo "current code embedded in:"
    echo "  templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml"
    echo ""
    echo "Example:"
    echo "  $0 Elite-Xbbit-MAP"
}

if [ $# -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 1
fi

PAYER_NAME="$1"
FUNCTION_NAME="${PAYER_NAME}-CloudFront-Alert"

# Resolve template path relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../templates/07-cloudfront-monitoring/cloudfront_monitoring.yaml"

if [ ! -f "$TEMPLATE" ]; then
    print_error "Template not found: $TEMPLATE"
    exit 1
fi

# 1. Verify the function exists
print_status "Checking Lambda function: $FUNCTION_NAME"
if ! aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
    print_error "Lambda function '$FUNCTION_NAME' not found in $REGION."
    print_error "Confirm the PayerName and that Module 7 is deployed for this Payer."
    exit 1
fi

# 2. Extract the embedded ZipFile Python code -> index.py
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
INDEX_PY="${WORK_DIR}/index.py"

print_status "Extracting Lambda code from template"
python3 - "$TEMPLATE" "$INDEX_PY" <<'PY'
import sys
template_path, out_path = sys.argv[1], sys.argv[2]
lines = open(template_path).read().split('\n')
start = None
for i, ln in enumerate(lines):
    if ln.strip() == 'ZipFile: |':
        start = i + 1
        break
if start is None:
    sys.exit("ZipFile block not found in template")
base = len(lines[start]) - len(lines[start].lstrip())
out = []
for ln in lines[start:]:
    if ln.strip() == '':
        out.append('')
        continue
    indent = len(ln) - len(ln.lstrip())
    if indent < base:
        break
    out.append(ln[base:])
code = '\n'.join(out).rstrip() + '\n'
# fail fast on syntax errors before we ship it
compile(code, 'index.py', 'exec')
open(out_path, 'w').write(code)
print(f"Extracted {len(out)} lines")
PY

# 3. Package
print_status "Packaging Lambda zip"
( cd "$WORK_DIR" && zip -q lambda.zip index.py )

# 4. Update function code
print_status "Updating function code: $FUNCTION_NAME"
aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://${WORK_DIR}/lambda.zip" \
    --region "$REGION" \
    --publish >/dev/null

# 5. Wait for update to settle
print_status "Waiting for LastUpdateStatus = Successful"
for _ in $(seq 1 30); do
    STATUS=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'Configuration.LastUpdateStatus' --output text)
    if [ "$STATUS" = "Successful" ]; then
        print_success "Lambda code updated for $FUNCTION_NAME"
        exit 0
    elif [ "$STATUS" = "Failed" ]; then
        print_error "Lambda update failed. Check the function in the console."
        exit 1
    fi
    sleep 2
done

print_warning "Timed out waiting for update confirmation (last status: $STATUS)."
print_warning "Verify manually with: aws lambda get-function --function-name $FUNCTION_NAME"
exit 1
