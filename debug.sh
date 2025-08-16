#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}🔍 Hostname Connectivity Diagnostic${NC}"
echo "====================================="
echo ""

# Check if we're in the right directory
if [ ! -f "kubernetes-the-hard-way/machines.txt" ]; then
    echo -e "${RED}❌ machines.txt not found. Run this from the project root directory.${NC}"
    exit 1
fi

cd kubernetes-the-hard-way

echo -e "${YELLOW}📋 Step 1: Checking local /etc/hosts${NC}"
echo ""
echo "Local /etc/hosts entries for Kubernetes nodes:"
grep -E "(server|node-0|node-1)" /etc/hosts || echo "No entries found"
echo ""

echo -e "${YELLOW}🔍 Step 2: Testing hostname resolution${NC}"
echo ""

for host in server node-0 node-1; do
    echo "Testing resolution for $host:"
    
    # Test with getent
    if getent hosts $host >/dev/null 2>&1; then
        IP=$(getent hosts $host | awk '{print $1}')
        echo -e "  ${GREEN}✅ getent resolves $host to $IP${NC}"
    else
        echo -e "  ${RED}❌ getent cannot resolve $host${NC}"
    fi
    
    # Test with ping (1 packet only)
    if ping -c 1 -W 2 $host >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ ping can reach $host${NC}"
    else
        echo -e "  ${RED}❌ ping cannot reach $host${NC}"
    fi
    
    echo ""
done

echo -e "${YELLOW}🔑 Step 3: Testing SSH key availability${NC}"
echo ""

# Check SSH keys
if [ -f ~/.ssh/id_rsa ]; then
    echo -e "${GREEN}✅ ~/.ssh/id_rsa exists${NC}"
else
    echo -e "${RED}❌ ~/.ssh/id_rsa missing${NC}"
fi

# Get PEM key path
KEY_PATH=$(terraform -chdir=.. output -json ssh_key_info | jq -r '.private_key_path' 2>/dev/null || echo "")
if [ -n "$KEY_PATH" ] && [ -f "$KEY_PATH" ]; then
    echo -e "${GREEN}✅ PEM key exists at $KEY_PATH${NC}"
else
    echo -e "${RED}❌ PEM key not found${NC}"
fi

echo ""

echo -e "${YELLOW}🧪 Step 4: Testing direct IP SSH connections${NC}"
echo ""

# Get IPs from Terraform
CONTROLLER_PUBLIC_IP=$(terraform -chdir=.. output -raw controller_public_ip 2>/dev/null || echo "")
WORKER_0_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-0".public_ip' 2>/dev/null || echo "")
WORKER_1_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-1".public_ip' 2>/dev/null || echo "")

# Test IP-based connections
declare -A HOST_IPS=( 
    ["server"]="$CONTROLLER_PUBLIC_IP"
    ["node-0"]="$WORKER_0_PUBLIC_IP" 
    ["node-1"]="$WORKER_1_PUBLIC_IP"
)

for host in server node-0 node-1; do
    ip=${HOST_IPS[$host]}
    if [ -z "$ip" ]; then
        echo -e "  ${RED}❌ No IP found for $host${NC}"
        continue
    fi
    
    echo "Testing SSH to $host ($ip):"
    
    # Test with id_rsa
    if [ -f ~/.ssh/id_rsa ]; then
        if timeout 10 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes root@$ip hostname >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ SSH with id_rsa to $ip works${NC}"
        else
            echo -e "  ${RED}❌ SSH with id_rsa to $ip failed${NC}"
        fi
    fi
    
    # Test with PEM key
    if [ -n "$KEY_PATH" ] && [ -f "$KEY_PATH" ]; then
        if timeout 10 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i "$KEY_PATH" root@$ip hostname >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ SSH with PEM key to $ip works${NC}"
        else
            echo -e "  ${RED}❌ SSH with PEM key to $ip failed${NC}"
        fi
    fi
    
    echo ""
done

echo -e "${YELLOW}🧪 Step 5: Testing hostname-based SSH connections${NC}"
echo ""

for host in server node-0 node-1; do
    echo "Testing hostname-based SSH to $host:"
    
    # Test with id_rsa
    if [ -f ~/.ssh/id_rsa ]; then
        if timeout 10 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes root@$host hostname >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ SSH with id_rsa to $host works${NC}"
        else
            echo -e "  ${RED}❌ SSH with id_rsa to $host failed${NC}"
        fi
    fi
    
    # Test with PEM key
    if [ -n "$KEY_PATH" ] && [ -f "$KEY_PATH" ]; then
        if timeout 10 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i "$KEY_PATH" root@$host hostname >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ SSH with PEM key to $host works${NC}"
        else
            echo -e "  ${RED}❌ SSH with PEM key to $host failed${NC}"
        fi
    fi
    
    echo ""
done

echo -e "${YELLOW}📝 Step 6: Checking SSH agent and key loading${NC}"
echo ""

# Check SSH agent
if [ -n "$SSH_AUTH_SOCK" ]; then
    echo -e "${GREEN}✅ SSH agent is running${NC}"
    
    # List loaded keys
    ssh-add -l 2>/dev/null | while read line; do
        echo "  Loaded key: $line"
    done || echo "  No keys loaded in SSH agent"
else
    echo -e "${YELLOW}⚠️  SSH agent not running${NC}"
fi

echo ""

echo -e "${BLUE}🔧 Recommendations:${NC}"
echo "===================="
echo ""

# Check if hostname resolution works
RESOLUTION_WORKS=true
for host in server node-0 node-1; do
    if ! getent hosts $host >/dev/null 2>&1; then
        RESOLUTION_WORKS=false
        break
    fi
done

if [ "$RESOLUTION_WORKS" = "false" ]; then
    echo -e "${YELLOW}1. Hostname resolution issue detected${NC}"
    echo "   Try: sudo systemctl restart systemd-resolved"
    echo "   Or reload /etc/hosts: sudo service networking restart"
    echo ""
fi

# Check if SSH keys need to be loaded
if [ -f ~/.ssh/id_rsa ] && ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf ~/.ssh/id_rsa | awk '{print $2}')"; then
    echo -e "${YELLOW}2. SSH key not loaded in agent${NC}"
    echo "   Try: ssh-add ~/.ssh/id_rsa"
    echo ""
fi

echo -e "${YELLOW}3. Alternative connection methods:${NC}"
echo "   Use IP-based connections:"
if [ -n "$CONTROLLER_PUBLIC_IP" ]; then
    echo "   ssh root@$CONTROLLER_PUBLIC_IP  # server"
fi
if [ -n "$WORKER_0_PUBLIC_IP" ]; then
    echo "   ssh root@$WORKER_0_PUBLIC_IP    # node-0"
fi
if [ -n "$WORKER_1_PUBLIC_IP" ]; then
    echo "   ssh root@$WORKER_1_PUBLIC_IP    # node-1"
fi
echo ""

cd ..
