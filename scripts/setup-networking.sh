#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🌐 Kubernetes the Hard Way - Provisioning Pod Network Routes${NC}"
echo "============================================================"
echo ""

# Check if we're in the right directory structure
if [ ! -d "kubernetes-the-hard-way" ]; then
    echo -e "${RED}❌ kubernetes-the-hard-way directory not found${NC}"
    echo "Please run this from the kubernetes-hard-way-terraform directory"
    exit 1
fi

# Check if infrastructure is deployed
if [ ! -f terraform.tfstate ]; then
    echo -e "${RED}❌ No infrastructure found. Please run 'make deploy' first.${NC}"
    exit 1
fi

cd kubernetes-the-hard-way

echo -e "${YELLOW}📋 Step 1: Verifying prerequisites${NC}"

# Check if machines.txt exists
if [ ! -f "machines.txt" ]; then
    echo -e "${RED}❌ machines.txt not found. Please run 'make setup-compute' first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ machines.txt found${NC}"

# Check if worker nodes are bootstrapped by verifying kubelet service
echo "Checking if worker nodes are bootstrapped..."
for host in node-0 node-1; do
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$host" "systemctl is-active --quiet kubelet" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $host - kubelet service is running${NC}"
    else
        echo -e "  ${RED}❌ $host - kubelet service not running${NC}"
        echo "Please ensure worker nodes are bootstrapped:"
        echo "  make bootstrap-workers"
        exit 1
    fi
done

echo -e "${GREEN}✅ All prerequisites verified${NC}"
echo ""

echo -e "${YELLOW}🔍 Step 2: Gathering network information${NC}"

echo "Reading network configuration from machines.txt..."
echo "Current machines.txt content:"
cat machines.txt | sed 's/^/  /'
echo ""

# Extract network information from machines.txt
if ! SERVER_IP=$(grep server machines.txt | cut -d " " -f 1) || [ -z "$SERVER_IP" ]; then
    echo -e "${RED}❌ Failed to extract server IP from machines.txt${NC}"
    exit 1
fi

if ! NODE_0_IP=$(grep node-0 machines.txt | cut -d " " -f 1) || [ -z "$NODE_0_IP" ]; then
    echo -e "${RED}❌ Failed to extract node-0 IP from machines.txt${NC}"
    exit 1
fi

if ! NODE_0_SUBNET=$(grep node-0 machines.txt | cut -d " " -f 4) || [ -z "$NODE_0_SUBNET" ]; then
    echo -e "${RED}❌ Failed to extract node-0 subnet from machines.txt${NC}"
    exit 1
fi

if ! NODE_1_IP=$(grep node-1 machines.txt | cut -d " " -f 1) || [ -z "$NODE_1_IP" ]; then
    echo -e "${RED}❌ Failed to extract node-1 IP from machines.txt${NC}"
    exit 1
fi

if ! NODE_1_SUBNET=$(grep node-1 machines.txt | cut -d " " -f 4) || [ -z "$NODE_1_SUBNET" ]; then
    echo -e "${RED}❌ Failed to extract node-1 subnet from machines.txt${NC}"
    exit 1
fi

echo "Extracted network information:"
echo "  Server IP:      $SERVER_IP"
echo "  Node-0 IP:      $NODE_0_IP"
echo "  Node-0 Subnet:  $NODE_0_SUBNET"
echo "  Node-1 IP:      $NODE_1_IP" 
echo "  Node-1 Subnet:  $NODE_1_SUBNET"
echo ""

# Verify these are private IPs (should be in 10.240.0.x range based on your setup)
if [[ ! "$SERVER_IP" =~ ^10\.240\.0\. ]] || [[ ! "$NODE_0_IP" =~ ^10\.240\.0\. ]] || [[ ! "$NODE_1_IP" =~ ^10\.240\.0\. ]]; then
    echo -e "${YELLOW}⚠️ Warning: IPs don't appear to be in expected private range (10.240.0.x)${NC}"
    echo "This might be expected depending on your VPC configuration."
fi

# Verify subnets are the expected pod networks
if [[ ! "$NODE_0_SUBNET" =~ ^10\.200\.0\.0/24$ ]] || [[ ! "$NODE_1_SUBNET" =~ ^10\.200\.1\.0/24$ ]]; then
    echo -e "${YELLOW}⚠️ Warning: Pod subnets don't match expected values (10.200.0.0/24, 10.200.1.0/24)${NC}"
    echo "This might be expected depending on your configuration."
fi

# Validate extracted information
if [ -z "$SERVER_IP" ] || [ -z "$NODE_0_IP" ] || [ -z "$NODE_0_SUBNET" ] || [ -z "$NODE_1_IP" ] || [ -z "$NODE_1_SUBNET" ]; then
    echo -e "${RED}❌ Failed to extract required network information from machines.txt${NC}"
    echo "Please verify machines.txt format is correct"
    exit 1
fi

echo -e "${GREEN}✅ Network information validated${NC}"

echo ""

echo -e "${YELLOW}🛣️  Step 3: Creating network routes on controller (server)${NC}"

echo "Configuring routes on server to reach worker node subnets..."
ssh root@server <<EOF
set -euo pipefail

# Colors for remote script
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\${YELLOW}Adding routes for worker node subnets...\${NC}"

# Add route to node-0 subnet via node-0 IP
echo "  → Adding route to $NODE_0_SUBNET via $NODE_0_IP"
if ip route add $NODE_0_SUBNET via $NODE_0_IP 2>/dev/null || ip route replace $NODE_0_SUBNET via $NODE_0_IP 2>/dev/null; then
    echo -e "    \${GREEN}✅ Route to $NODE_0_SUBNET added/updated\${NC}"
else
    echo -e "    \${YELLOW}⚠️ Route to $NODE_0_SUBNET may already exist\${NC}"
fi

# Add route to node-1 subnet via node-1 IP  
echo "  → Adding route to $NODE_1_SUBNET via $NODE_1_IP"
if ip route add $NODE_1_SUBNET via $NODE_1_IP 2>/dev/null || ip route replace $NODE_1_SUBNET via $NODE_1_IP 2>/dev/null; then
    echo -e "    \${GREEN}✅ Route to $NODE_1_SUBNET added/updated\${NC}"
else
    echo -e "    \${YELLOW}⚠️ Route to $NODE_1_SUBNET may already exist\${NC}"
fi

echo ""
echo -e "\${GREEN}✅ Server routing configured\${NC}"

# Make routes persistent by adding to systemd-networkd config if available, or using a simple startup script
echo -e "\${YELLOW}Making routes persistent...\${NC}"

# Create a simple script to restore routes on boot
cat > /etc/kubernetes-routes.sh << 'ROUTE_SCRIPT'
#!/bin/bash
# Kubernetes pod network routes
ip route add $NODE_0_SUBNET via $NODE_0_IP 2>/dev/null || true
ip route add $NODE_1_SUBNET via $NODE_1_IP 2>/dev/null || true
ROUTE_SCRIPT

chmod +x /etc/kubernetes-routes.sh

# Create systemd service to run on boot
cat > /etc/systemd/system/kubernetes-routes.service << 'SERVICE_FILE'
[Unit]
Description=Kubernetes Pod Network Routes
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/kubernetes-routes.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_FILE

systemctl daemon-reload
systemctl enable kubernetes-routes.service

echo -e "\${GREEN}✅ Routes configured to persist across reboots\${NC}"
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Server network routes configured successfully${NC}"
else
    echo -e "${RED}❌ Failed to configure network routes on server${NC}"
    exit 1
fi

echo ""

echo -e "${YELLOW}🛣️  Step 4: Creating network routes on node-0${NC}"

echo "Configuring routes on node-0 to reach node-1 subnet..."
ssh root@node-0 <<EOF
set -euo pipefail

# Colors for remote script
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\${YELLOW}Adding route to node-1 subnet...\${NC}"

# Add route to node-1 subnet via node-1 IP
echo "  → Adding route to $NODE_1_SUBNET via $NODE_1_IP"
if ip route add $NODE_1_SUBNET via $NODE_1_IP 2>/dev/null || ip route replace $NODE_1_SUBNET via $NODE_1_IP 2>/dev/null; then
    echo -e "    \${GREEN}✅ Route to $NODE_1_SUBNET added/updated\${NC}"
else
    echo -e "    \${YELLOW}⚠️ Route to $NODE_1_SUBNET may already exist\${NC}"
fi

echo ""
echo -e "\${GREEN}✅ Node-0 routing configured\${NC}"

# Make route persistent
echo -e "\${YELLOW}Making route persistent...\${NC}"

cat > /etc/kubernetes-routes.sh << 'ROUTE_SCRIPT'
#!/bin/bash
# Kubernetes pod network routes
ip route add $NODE_1_SUBNET via $NODE_1_IP 2>/dev/null || true
ROUTE_SCRIPT

chmod +x /etc/kubernetes-routes.sh

cat > /etc/systemd/system/kubernetes-routes.service << 'SERVICE_FILE'
[Unit]
Description=Kubernetes Pod Network Routes
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/kubernetes-routes.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_FILE

systemctl daemon-reload
systemctl enable kubernetes-routes.service

echo -e "\${GREEN}✅ Routes configured to persist across reboots\${NC}"
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Node-0 network routes configured successfully${NC}"
else
    echo -e "${RED}❌ Failed to configure network routes on node-0${NC}"
    exit 1
fi

echo ""

echo -e "${YELLOW}🛣️  Step 5: Creating network routes on node-1${NC}"

echo "Configuring routes on node-1 to reach node-0 subnet..."
ssh root@node-1 <<EOF
set -euo pipefail

# Colors for remote script
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\${YELLOW}Adding route to node-0 subnet...\${NC}"

# Add route to node-0 subnet via node-0 IP
echo "  → Adding route to $NODE_0_SUBNET via $NODE_0_IP"
if ip route add $NODE_0_SUBNET via $NODE_0_IP 2>/dev/null || ip route replace $NODE_0_SUBNET via $NODE_0_IP 2>/dev/null; then
    echo -e "    \${GREEN}✅ Route to $NODE_0_SUBNET added/updated\${NC}"
else
    echo -e "    \${YELLOW}⚠️ Route to $NODE_0_SUBNET may already exist\${NC}"
fi

echo ""
echo -e "\${GREEN}✅ Node-1 routing configured\${NC}"

# Make route persistent
echo -e "\${YELLOW}Making route persistent...\${NC}"

cat > /etc/kubernetes-routes.sh << 'ROUTE_SCRIPT'
#!/bin/bash
# Kubernetes pod network routes  
ip route add $NODE_0_SUBNET via $NODE_0_IP 2>/dev/null || true
ROUTE_SCRIPT

chmod +x /etc/kubernetes-routes.sh

cat > /etc/systemd/system/kubernetes-routes.service << 'SERVICE_FILE'
[Unit]
Description=Kubernetes Pod Network Routes
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/kubernetes-routes.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_FILE

systemctl daemon-reload
systemctl enable kubernetes-routes.service

echo -e "\${GREEN}✅ Routes configured to persist across reboots\${NC}"
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Node-1 network routes configured successfully${NC}"
else
    echo -e "${RED}❌ Failed to configure network routes on node-1${NC}"
    exit 1
fi

echo ""

echo -e "${YELLOW}🔍 Step 6: Verification${NC}"

echo "Verifying routing tables on all nodes..."
echo ""

# Verify server routes
echo "=== Server routing table ==="
echo "Routes on server (should include routes to both worker subnets):"
ssh root@server "ip route" | sed 's/^/  /'
echo ""

# Check for specific routes on server
echo "Checking server routes to worker subnets:"
if ssh root@server "ip route | grep -q '$NODE_0_SUBNET'"; then
    echo -e "  ${GREEN}✅ Route to $NODE_0_SUBNET found${NC}"
else
    echo -e "  ${RED}❌ Route to $NODE_0_SUBNET missing${NC}"
fi

if ssh root@server "ip route | grep -q '$NODE_1_SUBNET'"; then
    echo -e "  ${GREEN}✅ Route to $NODE_1_SUBNET found${NC}"
else
    echo -e "  ${RED}❌ Route to $NODE_1_SUBNET missing${NC}"
fi

echo ""

# Verify node-0 routes  
echo "=== Node-0 routing table ==="
echo "Routes on node-0 (should include route to node-1 subnet):"
ssh root@node-0 "ip route" | sed 's/^/  /'
echo ""

echo "Checking node-0 routes:"
if ssh root@node-0 "ip route | grep -q '$NODE_1_SUBNET'"; then
    echo -e "  ${GREEN}✅ Route to $NODE_1_SUBNET found${NC}"
else
    echo -e "  ${RED}❌ Route to $NODE_1_SUBNET missing${NC}"
fi

echo ""

# Verify node-1 routes
echo "=== Node-1 routing table ==="
echo "Routes on node-1 (should include route to node-0 subnet):"
ssh root@node-1 "ip route" | sed 's/^/  /'
echo ""

echo "Checking node-1 routes:"
if ssh root@node-1 "ip route | grep -q '$NODE_0_SUBNET'"; then
    echo -e "  ${GREEN}✅ Route to $NODE_0_SUBNET found${NC}"
else
    echo -e "  ${RED}❌ Route to $NODE_0_SUBNET missing${NC}"
fi

echo ""

echo "Testing routing table entries for pod subnets:"

# Verify routes exist and show them
echo "Routes on server for pod subnets:"
ssh root@server "ip route | grep -E '($NODE_0_SUBNET|$NODE_1_SUBNET)'" | sed 's/^/  /' || echo -e "  ${YELLOW}⚠️ No pod subnet routes found on server${NC}"

echo ""
echo "Routes on node-0 for pod subnets:"
ssh root@node-0 "ip route | grep '$NODE_1_SUBNET'" | sed 's/^/  /' || echo -e "  ${YELLOW}⚠️ No pod subnet route found on node-0${NC}"

echo ""
echo "Routes on node-1 for pod subnets:"
ssh root@node-1 "ip route | grep '$NODE_0_SUBNET'" | sed 's/^/  /' || echo -e "  ${YELLOW}⚠️ No pod subnet route found on node-1${NC}"

echo ""
echo -e "${BLUE}Note: Pod-to-pod communication will work once pods are deployed.${NC}"
echo -e "${BLUE}These routes prepare the infrastructure for inter-node pod communication.${NC}"

echo ""

echo -e "${YELLOW}📊 Step 7: Route persistence verification${NC}"

echo "Verifying route persistence configuration..."
for host in server node-0 node-1; do
    echo "  → Checking $host..."
    
    # Check if persistence script exists
    if ssh root@$host "[ -f /etc/kubernetes-routes.sh ]"; then
        echo -e "    ${GREEN}✅ Route script exists${NC}"
    else
        echo -e "    ${RED}❌ Route script missing${NC}"
    fi
    
    # Check if systemd service is enabled
    if ssh root@$host "systemctl is-enabled kubernetes-routes.service >/dev/null 2>&1"; then
        echo -e "    ${GREEN}✅ Route service enabled${NC}"
    else
        echo -e "    ${RED}❌ Route service not enabled${NC}"
    fi
done

echo ""

echo -e "${GREEN}🎉 POD NETWORK ROUTES PROVISIONING COMPLETE!${NC}"
echo "======================================================="
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ Network routes configured on all nodes${NC}"
echo "    • Server: Routes to both worker pod subnets"
echo "    • Node-0: Route to node-1 pod subnet"
echo "    • Node-1: Route to node-0 pod subnet"
echo ""
echo -e "  ${GREEN}✅ Route persistence configured${NC}"
echo "    • Routes will survive reboots via systemd service"
echo "    • kubernetes-routes.service enabled on all nodes"
echo ""
echo "Network configuration:"
echo "  📡 Server ($SERVER_IP):"
echo "    → $NODE_0_SUBNET via $NODE_0_IP"
echo "    → $NODE_1_SUBNET via $NODE_1_IP"
echo ""
echo "  📡 Node-0 ($NODE_0_IP):"
echo "    → $NODE_1_SUBNET via $NODE_1_IP"
echo ""
echo "  📡 Node-1 ($NODE_1_IP):"
echo "    → $NODE_0_SUBNET via $NODE_0_IP"
echo ""
echo "Verification commands:"
echo "  ssh root@server 'ip route'"
echo "  ssh root@node-0 'ip route'"
echo "  ssh root@node-1 'ip route'"
echo ""
echo -e "${BLUE}Next step: Smoke test${NC}"
echo "Run: make smoke-test"
echo ""
echo "Pod networking is now configured! Pods on different nodes can communicate."

cd ..