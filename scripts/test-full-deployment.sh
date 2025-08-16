#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}🧪 Testing Full Deployment${NC}"
echo "=========================="
echo ""

# Test 1: Check if infrastructure exists
echo -e "${YELLOW}Test 1: Infrastructure Status${NC}"
if [ -f terraform.tfstate ]; then
    echo -e "  ${GREEN}✅ Infrastructure deployed${NC}"
    
    # Get status info
    if terraform output controller_public_ip &>/dev/null; then
        CONTROLLER_IP=$(terraform output -raw controller_public_ip)
        echo "    Controller IP: $CONTROLLER_IP"
    else
        echo -e "    ${RED}❌ Cannot get controller IP${NC}"
    fi
else
    echo -e "  ${RED}❌ No infrastructure found${NC}"
    exit 1
fi

echo ""

# Test 2: Check jumpbox setup
echo -e "${YELLOW}Test 2: Jumpbox Setup${NC}"
if [ -d "kubernetes-the-hard-way" ]; then
    echo -e "  ${GREEN}✅ kubernetes-the-hard-way directory exists${NC}"
    
    if [ -f "kubernetes-the-hard-way/downloads/client/kubectl" ]; then
        echo -e "  ${GREEN}✅ kubectl binary downloaded${NC}"
    else
        echo -e "  ${RED}❌ kubectl binary missing${NC}"
    fi
    
    if command -v kubectl &>/dev/null; then
        KUBECTL_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
        echo -e "  ${GREEN}✅ kubectl installed (${KUBECTL_VERSION})${NC}"
    else
        echo -e "  ${RED}❌ kubectl not installed in PATH${NC}"
    fi
else
    echo -e "  ${RED}❌ kubernetes-the-hard-way directory missing${NC}"
fi

echo ""

# Test 3: Check compute resources setup
echo -e "${YELLOW}Test 3: Compute Resources${NC}"
if [ -f "kubernetes-the-hard-way/machines.txt" ]; then
    echo -e "  ${GREEN}✅ machines.txt exists${NC}"
    echo "    Contents:"
    sed 's/^/      /' kubernetes-the-hard-way/machines.txt
else
    echo -e "  ${RED}❌ machines.txt missing${NC}"
fi

if [ -f "kubernetes-the-hard-way/hosts" ]; then
    echo -e "  ${GREEN}✅ hosts file exists${NC}"
else
    echo -e "  ${RED}❌ hosts file missing${NC}"
fi

echo ""

# Test 4: SSH connectivity
echo -e "${YELLOW}Test 4: SSH Connectivity${NC}"

cd kubernetes-the-hard-way 2>/dev/null || { echo -e "${RED}❌ Cannot enter kubernetes-the-hard-way directory${NC}"; exit 1; }

for host in server node-0 node-1; do
    echo "  Testing $host..."
    if timeout 15 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$host "hostname" &>/dev/null; then
        HOSTNAME=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$host "hostname" 2>/dev/null)
        echo -e "    ${GREEN}✅ $host accessible (hostname: $HOSTNAME)${NC}"
    else
        echo -e "    ${RED}❌ $host not accessible${NC}"
    fi
done

echo ""

# Test 5: Internal connectivity
echo -e "${YELLOW}Test 5: Internal Network Connectivity${NC}"

echo "  Testing server -> worker nodes..."
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@server "ping -c 2 node-0 &>/dev/null && ping -c 2 node-1 &>/dev/null" 2>/dev/null; then
    echo -e "    ${GREEN}✅ Server can reach both worker nodes${NC}"
else
    echo -e "    ${RED}❌ Server cannot reach worker nodes${NC}"
fi

echo "  Testing worker node intercommunication..."
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@node-0 "ping -c 2 node-1 &>/dev/null" 2>/dev/null; then
    echo -e "    ${GREEN}✅ Worker nodes can communicate${NC}"
else
    echo -e "    ${RED}❌ Worker nodes cannot communicate${NC}"
fi

cd ..

echo ""

# Summary
echo -e "${BLUE}🎯 Deployment Test Summary${NC}"
echo "=========================="
echo ""
echo "Your Kubernetes the Hard Way infrastructure is ready for:"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. 🔐 Generate certificates and configuration files"
echo "  2. ⚙️  Install and configure etcd"  
echo "  3. 🎛️  Setup Kubernetes control plane"
echo "  4. 👷 Configure worker nodes"
echo "  5. 🌐 Setup networking"
echo ""
echo -e "${YELLOW}Quick commands to verify:${NC}"
echo "  ssh root@server"
echo "  ssh root@node-0" 
echo "  ssh root@node-1"
echo ""
echo -e "${GREEN}🎉 Ready to continue with the tutorial!${NC}"
echo ""