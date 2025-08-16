#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Banner
echo -e "${GREEN}"
cat << 'EOF'
╦╔═╗╦ ╦╔╗ ╔═╗╦═╗╔╗╔╔═╗╔╦╗╔═╗╔═╗  ╔╦╗╦ ╦╔═╗  ╦ ╦╔═╗╦═╗╔╦╗  ╦ ╦╔═╗╦ ╦
╠╩╗ ║ ║╠╩╗║╣ ╠╦╝║║║║╣  ║ ║╣ ╚═╗   ║ ╠═╣║╣   ╠═╣╠═╣╠╦╝ ║║  ║║║╠═╣╚╦╝
╩ ╩ ╚═╝╚═╝╚═╝╩╚═╝╚╝╚═╝ ╩ ╚═╝╚═╝   ╩ ╩ ╩╚═╝  ╩ ╩╩ ╩╩╚══╩╝  ╚╩╝╩ ╩ ╩ 
Automated Terraform Deployment
EOF
echo -e "${NC}"

echo -e "🔍 Validating Prerequisites..."
echo ""

ERRORS=0

# Check if running on WSL Debian
echo -e "📋 Checking environment..."
if grep -q "debian" /etc/os-release 2>/dev/null; then
    echo -e "  ${GREEN}✅ Running on Debian${NC}"
else
    echo -e "  ${RED}❌ Not running on Debian${NC}"
    echo "     This setup is designed for WSL Debian. Please use Debian environment."
    ERRORS=$((ERRORS + 1))
fi

# Check if AWS CLI is installed
echo ""
echo -e "☁️  Checking AWS CLI..."
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    echo -e "  ${GREEN}✅ AWS CLI installed (version: $AWS_VERSION)${NC}"
    
    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        REGION=$(aws configure get region || echo "default")
        echo -e "  ${GREEN}✅ AWS credentials configured${NC}"
        echo "     Account ID: $ACCOUNT_ID"
        echo "     Region: $REGION"
    else
        echo -e "  ${RED}❌ AWS credentials not configured${NC}"
        echo "     Run: aws configure"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ${RED}❌ AWS CLI not installed${NC}"
    echo "     Install with:"
    echo "     curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
    echo "     unzip awscliv2.zip && sudo ./aws/install"
    ERRORS=$((ERRORS + 1))
fi

# Check if Terraform is installed
echo ""
echo -e "🏗️  Checking Terraform..."
if command -v terraform &> /dev/null; then
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    echo -e "  ${GREEN}✅ Terraform installed (version: $TERRAFORM_VERSION)${NC}"
    
    # Check if version is >= 1.0
    if [[ "$(printf '%s\n' "1.0.0" "$TERRAFORM_VERSION" | sort -V | head -n1)" = "1.0.0" ]]; then
        echo -e "  ${GREEN}✅ Terraform version is compatible${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Terraform version might be too old (< 1.0.0)${NC}"
    fi
else
    echo -e "  ${RED}❌ Terraform not installed${NC}"
    echo "     Install with:"
    echo "     wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
    echo "     echo 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main' | sudo tee /etc/apt/sources.list.d/hashicorp.list"
    echo "     sudo apt update && sudo apt install terraform"
    ERRORS=$((ERRORS + 1))
fi

# Check if jq is installed
echo ""
echo -e "🔧 Checking required tools..."
if command -v jq &> /dev/null; then
    echo -e "  ${GREEN}✅ jq installed${NC}"
else
    echo -e "  ${YELLOW}⚠️  jq not installed${NC}"
    echo "     Installing jq..."
    if sudo apt-get update && sudo apt-get install -y jq; then
        echo -e "  ${GREEN}✅ jq installed successfully${NC}"
    else
        echo -e "  ${RED}❌ Failed to install jq${NC}"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check if git is installed
if command -v git &> /dev/null; then
    echo -e "  ${GREEN}✅ git installed${NC}"
else
    echo -e "  ${YELLOW}⚠️  git not installed${NC}"
    echo "     Installing git..."
    if sudo apt-get install -y git; then
        echo -e "  ${GREEN}✅ git installed successfully${NC}"
    else
        echo -e "  ${RED}❌ Failed to install git${NC}"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check if terraform.tfvars exists
echo ""
echo -e "📝 Checking configuration..."
if [ -f "terraform.tfvars" ]; then
    echo -e "  ${GREEN}✅ terraform.tfvars found${NC}"
    
    # Validate required variables
    if grep -q "key_name" terraform.tfvars; then
        KEY_NAME=$(grep "key_name" terraform.tfvars | cut -d'"' -f2)
        echo -e "  ${GREEN}✅ key_name configured: $KEY_NAME${NC}"
        
        # Check if key pair exists in AWS
        if aws ec2 describe-key-pairs --key-names "$KEY_NAME" &> /dev/null; then
            echo -e "  ${GREEN}✅ AWS key pair exists${NC}"
        else
            echo -e "  ${YELLOW}⚠️  AWS key pair '$KEY_NAME' not found${NC}"
            echo "     Will be created during setup"
        fi
        
        # Check if local key file exists
        if [ -f "$HOME/.ssh/$KEY_NAME.pem" ]; then
            echo -e "  ${GREEN}✅ Local SSH key found${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Local SSH key not found${NC}"
            echo "     Will be created during setup"
        fi
    else
        echo -e "  ${RED}❌ key_name not configured in terraform.tfvars${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ${RED}❌ terraform.tfvars not found${NC}"
    echo "     Copy terraform.tfvars.example to terraform.tfvars and configure it"
    ERRORS=$((ERRORS + 1))
fi

# Summary
echo ""
echo "==============================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All prerequisites validated successfully!${NC}"
    echo "   Ready to deploy infrastructure."
else
    echo -e "${RED}❌ Found $ERRORS error(s) that need to be fixed.${NC}"
    echo "   Please resolve the issues above before proceeding."
    exit 1
fi
echo "==============================================="