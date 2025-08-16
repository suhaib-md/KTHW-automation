#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🗄️  Kubernetes the Hard Way - Bootstrap etcd Cluster${NC}"
echo "===================================================="
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

# Check prerequisites
echo -e "${YELLOW}📋 Step 1: Verifying prerequisites${NC}"

# Check if certificates exist
required_files=("ca.crt" "kube-api-server.key" "kube-api-server.crt" "encryption-config.yaml")
missing_files=()

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✅ $file${NC}"
    else
        echo -e "  ${RED}❌ $file${NC}"
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo -e "${RED}❌ Missing required files: ${missing_files[*]}${NC}"
    echo "Please run the following commands first:"
    echo "  make generate-certs"
    echo "  make generate-configs"
    echo "  make generate-encryption"
    exit 1
fi

# Check if downloads directory exists
if [ ! -d "downloads" ]; then
    echo -e "${RED}❌ downloads directory not found${NC}"
    echo "Please ensure the kubernetes-the-hard-way repository is properly cloned"
    exit 1
fi

# Check if etcd binaries exist
if [ ! -f "downloads/controller/etcd" ]; then
    echo -e "${RED}❌ etcd binary not found at downloads/controller/etcd${NC}"
    exit 1
fi

if [ ! -f "downloads/client/etcdctl" ]; then
    echo -e "${RED}❌ etcdctl binary not found at downloads/client/etcdctl${NC}"
    exit 1
fi

# Check if etcd service file exists
if [ ! -f "units/etcd.service" ]; then
    echo -e "${RED}❌ etcd.service not found at units/etcd.service${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites verified${NC}"
echo ""

echo -e "${YELLOW}📦 Step 2: Copying etcd binaries and systemd unit files${NC}"

# Test connectivity to server
echo "Testing connectivity to server..."
if ! timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@server" "echo 'Connection test'" >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to server${NC}"
    echo "Please ensure 'make setup-compute' has been run and SSH connectivity is working"
    exit 1
fi
echo -e "${GREEN}✅ Connected to server${NC}"

# Copy etcd binaries and service file to server
echo "Copying etcd binaries and systemd unit file to server..."
scp downloads/controller/etcd \
    downloads/client/etcdctl \
    units/etcd.service \
    root@server:~/

echo -e "${GREEN}✅ Files copied to server${NC}"
echo ""

echo -e "${YELLOW}🔧 Step 3: Bootstrapping etcd cluster on server${NC}"

# SSH to server and bootstrap etcd
echo "Connecting to server and bootstrapping etcd..."
ssh root@server << 'EOF'
set -euo pipefail

# Colors for remote script
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Installing etcd binaries...${NC}"

# Install the etcd binaries
{
  mv etcd etcdctl /usr/local/bin/
  chmod +x /usr/local/bin/etcd /usr/local/bin/etcdctl
}

# Verify binaries are installed and working
if ! /usr/local/bin/etcd --version >/dev/null 2>&1; then
    echo -e "${RED}❌ etcd binary installation failed${NC}"
    exit 1
fi

if ! /usr/local/bin/etcdctl version >/dev/null 2>&1; then
    echo -e "${RED}❌ etcdctl binary installation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ etcd binaries installed successfully${NC}"

# Show versions (temporarily disable pipefail for version commands)
echo "Installed versions:"
set +o pipefail
ETCD_VERSION=$(/usr/local/bin/etcd --version 2>/dev/null | head -1 || echo "Version unavailable")
ETCDCTL_VERSION=$(/usr/local/bin/etcdctl version 2>/dev/null | head -1 || echo "Version unavailable")
set -o pipefail
echo "  etcd: $ETCD_VERSION"
echo "  etcdctl: $ETCDCTL_VERSION"

echo ""
echo -e "${YELLOW}Configuring etcd server...${NC}"

# Configure the etcd Server
{
  mkdir -p /etc/etcd /var/lib/etcd
  chmod 700 /var/lib/etcd
  cp ca.crt kube-api-server.key kube-api-server.crt /etc/etcd/
}

# Verify certificates were copied
if [ ! -f /etc/etcd/ca.crt ] || [ ! -f /etc/etcd/kube-api-server.key ] || [ ! -f /etc/etcd/kube-api-server.crt ]; then
    echo -e "${RED}❌ Failed to copy certificates to /etc/etcd/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ etcd directories created and certificates copied${NC}"

# Install systemd unit file
mv etcd.service /etc/systemd/system/

# Verify service file was moved
if [ ! -f /etc/systemd/system/etcd.service ]; then
    echo -e "${RED}❌ Failed to move etcd.service to /etc/systemd/system/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ etcd.service systemd unit file installed${NC}"

echo ""
echo -e "${YELLOW}Starting etcd server...${NC}"

# Start the etcd Server
{
  systemctl daemon-reload
  systemctl enable etcd
  systemctl start etcd
}

# Wait a moment for etcd to start
sleep 3

# Check if etcd is running
if systemctl is-active --quiet etcd; then
    echo -e "${GREEN}✅ etcd service is running${NC}"
else
    echo -e "${RED}❌ etcd service failed to start${NC}"
    echo "Service status:"
    systemctl status etcd --no-pager || true
    echo ""
    echo "Service logs:"
    journalctl -u etcd --no-pager -l --since="5 minutes ago" || true
    exit 1
fi

echo ""
echo -e "${YELLOW}Verifying etcd cluster...${NC}"

# Verification - List the etcd cluster members
echo "Testing etcd connectivity..."
if etcdctl member list >/dev/null 2>&1; then
    echo -e "${GREEN}✅ etcd cluster is accessible${NC}"
    echo ""
    echo "etcd cluster members:"
    etcdctl member list
else
    echo -e "${RED}❌ etcd cluster verification failed${NC}"
    echo ""
    echo "Debugging information:"
    echo "Service status:"
    systemctl status etcd --no-pager || true
    echo ""
    echo "Service logs (last 20 lines):"
    journalctl -u etcd --no-pager -n 20 || true
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 etcd cluster bootstrap completed successfully!${NC}"
EOF

# Check if the SSH session succeeded
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ etcd bootstrap completed on server${NC}"
else
    echo -e "${RED}❌ etcd bootstrap failed on server${NC}"
    echo "You can manually connect to server and check the logs:"
    echo "  ssh root@server"
    echo "  systemctl status etcd"
    echo "  journalctl -u etcd -f"
    exit 1
fi

echo ""

echo -e "${YELLOW}🔍 Step 4: Final verification from jumpbox${NC}"

# Test etcd connectivity from jumpbox through the server
echo "Testing etcd cluster status from jumpbox..."
if ssh root@server "etcdctl member list" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ etcd cluster is accessible from jumpbox${NC}"
    
    echo ""
    echo "etcd cluster information:"
    ssh root@server "etcdctl member list"
    
    echo ""
    echo "etcd cluster health:"
    ssh root@server "etcdctl endpoint health" 2>/dev/null || echo "Health check not available (normal for single node)"
    
    echo ""
    echo "etcd version:"
    ssh root@server "etcdctl version" | head -1
    
else
    echo -e "${YELLOW}⚠️ etcd verification from jumpbox failed, but may still be working${NC}"
    echo "You can manually verify by running:"
    echo "  ssh root@server"
    echo "  etcdctl member list"
fi

echo ""

echo -e "${GREEN}🎉 ETCD CLUSTER BOOTSTRAP COMPLETE!${NC}"
echo "============================================"
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ etcd and etcdctl binaries installed on controller${NC}"
echo -e "  ${GREEN}✅ etcd server configured with TLS certificates${NC}"
echo -e "  ${GREEN}✅ etcd.service systemd unit created and enabled${NC}"
echo -e "  ${GREEN}✅ etcd cluster started and verified${NC}"
echo ""
echo "etcd cluster details:"
ssh root@server "etcdctl member list" 2>/dev/null | sed 's/^/  /' || echo "  (Run 'ssh root@server etcdctl member list' to see details)"
echo ""
echo "Configuration:"
echo "  📁 Binary location: /usr/local/bin/{etcd,etcdctl}"
echo "  📁 Configuration: /etc/etcd/"
echo "  📁 Data directory: /var/lib/etcd/"
echo "  🔧 Service: etcd.service (enabled and running)"
echo ""
echo "Verification commands:"
echo "  ssh root@server 'systemctl status etcd'"
echo "  ssh root@server 'etcdctl member list'"
echo "  ssh root@server 'journalctl -u etcd -f'"
echo ""
echo -e "${BLUE}Next step: Bootstrap Kubernetes control plane${NC}"
echo "Run: make bootstrap-control-plane"
echo ""

cd ..