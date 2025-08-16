#!/bin/bash

set -e

# Make script executable
chmod +x "$(readlink -f "$0")" 2>/dev/null || true

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo -e "${YELLOW}🧹 Cleaning Up Jumpbox Setup${NC}"
echo "==============================="
echo ""

# Remove kubernetes-the-hard-way directory
if [ -d "kubernetes-the-hard-way" ]; then
    echo -e "${YELLOW}📁 Removing kubernetes-the-hard-way directory...${NC}"
    rm -rf kubernetes-the-hard-way
    echo -e "${GREEN}✅ Directory removed${NC}"
else
    echo -e "${GREEN}✅ kubernetes-the-hard-way directory already removed${NC}"
fi

# Remove kubectl from system (optional - ask user)
if [ -f "/usr/local/bin/kubectl" ]; then
    echo ""
    read -p "Remove kubectl from /usr/local/bin/kubectl? (y/N): " remove_kubectl
    if [[ $remove_kubectl =~ ^[Yy]$ ]]; then
        sudo rm -f /usr/local/bin/kubectl
        echo -e "${GREEN}✅ kubectl removed from system${NC}"
    else
        echo -e "${YELLOW}⚠️  kubectl left installed${NC}"
    fi
fi

# SSH keys cleanup info
echo ""
echo -e "${YELLOW}🔑 SSH Keys Information:${NC}"
if [ -f "$HOME/.ssh/kubernetes-hard-way.pem" ]; then
    echo -e "  ${YELLOW}⚠️  Local SSH keys still exist:${NC}"
    echo "     $HOME/.ssh/kubernetes-hard-way.pem"
    echo "     $HOME/.ssh/kubernetes-hard-way.pub"
    echo ""
    read -p "Remove local SSH keys? (y/N): " remove_keys
    if [[ $remove_keys =~ ^[Yy]$ ]]; then
        rm -f "$HOME/.ssh/kubernetes-hard-way.pem"
        rm -f "$HOME/.ssh/kubernetes-hard-way.pub"
        echo -e "${GREEN}✅ Local SSH keys removed${NC}"
    else
        echo -e "${YELLOW}⚠️  SSH keys left intact${NC}"
    fi
else
    echo -e "${GREEN}✅ No local SSH keys found${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Jumpbox cleanup complete!${NC}"
echo ""
echo "Note: System packages installed during jumpbox setup are left intact:"
echo "  - wget, curl, vim, openssl, git, jq, socat, conntrack, ipset"
echo "  You can remove these manually if desired."
echo ""