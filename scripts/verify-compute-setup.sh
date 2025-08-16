#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo -e "${YELLOW}🧪 Verifying Compute Resources Setup${NC}"
echo "====================================="
echo ""

# Check if we're in the right directory
if [ ! -f "kubernetes-the-hard-way/machines.txt" ]; then
    echo -e "${RED}❌ machines.txt not found. Please run 'make setup-compute' first.${NC}"
    exit 1
fi

cd kubernetes-the-hard-way

echo -e "${YELLOW}📋 Checking machines.txt file:${NC}"
cat machines.txt
echo ""

echo -e "${YELLOW}🔗 Testing hostname connectivity:${NC}"

# Test each machine
for host in server node-0 node-1; do
    echo "  Testing $host..."
    if timeout 10 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@$host "hostname && uptime" &>/dev/null; then
        echo -e "    ${GREEN}✅ $host is reachable${NC}"
    else
        echo -e "    ${RED}❌ $host is not reachable${NC}"
    fi
done

echo ""

echo -e "${YELLOW}🌐 Testing internal connectivity:${NC}"

# Test internal network connectivity between nodes
echo "  Testing server -> node-0..."
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@server "ping -c 1 node-0 &>/dev/null"; then
    echo -e "    ${GREEN}✅ server can reach node-0${NC}"
else
    echo -e "    ${RED}❌ server cannot reach node-0${NC}"
fi

echo "  Testing server -> node-1..."
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@server "ping -c 1 node-1 &>/dev/null"; then
    echo -e "    ${GREEN}✅ server can reach node-1${NC}"
else
    echo -e "    ${RED}❌ server cannot reach node-1${NC}"
fi

echo "  Testing node-0 -> node-1..."
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@node-0 "ping -c 1 node-1 &>/dev/null"; then
    echo -e "    ${GREEN}✅ node-0 can reach node-1${NC}"
else
    echo -e "    ${RED}❌ node-0 cannot reach node-1${NC}"
fi

echo ""

echo -e "${YELLOW}📊 System information:${NC}"

# Get system info from each machine
for host in server node-0 node-1; do
    echo "  $host:"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$host "
        echo '    Hostname: '$(hostname)
        echo '    OS: '$(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"')
        echo '    Kernel: '$(uname -r)
        echo '    Memory: '$(free -h | grep Mem | awk '{print $2}')
        echo '    CPU: '$(nproc)' cores'
        echo ''
    " 2>/dev/null || echo -e "    ${RED}❌ Failed to get info from $host${NC}"
done

echo ""
echo -e "${GREEN}✅ Compute resources verification complete!${NC}"
echo ""

cd ..