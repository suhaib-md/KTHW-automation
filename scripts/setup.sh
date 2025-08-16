#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Check prerequisites
print_header "=== Checking Prerequisites ==="

# Check if we're in WSL
if ! grep -q microsoft /proc/version; then
    print_error "This script is designed to run in WSL (Windows Subsystem for Linux)"
    exit 1
fi

# Variables
PROJECT_NAME="kubernetes-hard-way"
KEY_NAME=$(grep "key_name" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "kubernetes-hard-way")
AWS_REGION=$(grep "aws_region" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "us-west-2")

echo -e "🔧 Initial Setup for Kubernetes the Hard Way"
echo "============================================="
echo ""

# Create terraform.tfvars if it doesn't exist
if [ ! -f terraform.tfvars ]; then
    echo -e "📝 Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo -e "  ${YELLOW}⚠️  Please edit terraform.tfvars with your specific values!${NC}"
    echo "     File created at: $(pwd)/terraform.tfvars"
    echo ""
    echo -e "  ${RED}❌ Setup cannot continue without terraform.tfvars configuration${NC}"
    echo "     Edit the file and run 'make deploy' again."
    exit 1
fi

echo -e "📝 terraform.tfvars configuration found"
echo ""

echo -e "🔑 SSH Key Pair Management"
echo -e "  ✅ SSH key pairs will be created automatically by Terraform"
echo -e "  📁 Keys will be saved to:"
echo -e "     🔑 Private key: ~/.ssh/${KEY_NAME}.pem"
echo -e "     📄 Public key:  ~/.ssh/${KEY_NAME}.pub"
echo ""

echo -e "🔧 Setup completed successfully!"
echo "================================="
echo ""
echo "Configuration:"
echo "  📁 Project: $PROJECT_NAME"
echo "  🔑 Key Name: $KEY_NAME"
echo "  🌍 Region: $AWS_REGION"
echo "  📝 Config File: terraform.tfvars"
echo ""
echo "Ready for Terraform deployment..."