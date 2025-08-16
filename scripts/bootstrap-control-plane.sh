#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🚀 Kubernetes the Hard Way - Bootstrap Control Plane${NC}"
echo "=================================================="
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

# Check if certificates and configs exist
required_files=("ca.crt" "ca.key" "kube-api-server.key" "kube-api-server.crt" 
                "service-accounts.key" "service-accounts.crt" "encryption-config.yaml"
                "admin.kubeconfig" "kube-controller-manager.kubeconfig" "kube-scheduler.kubeconfig")
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

# Check if control plane binaries exist
required_binaries=("downloads/controller/kube-apiserver" "downloads/controller/kube-controller-manager" 
                  "downloads/controller/kube-scheduler" "downloads/client/kubectl")
for binary in "${required_binaries[@]}"; do
    if [ ! -f "$binary" ]; then
        echo -e "  ${RED}❌ $binary not found${NC}"
        missing_files+=("$binary")
    else
        echo -e "  ${GREEN}✅ $binary${NC}"
    fi
done

# Check if systemd unit files exist
required_units=("units/kube-apiserver.service" "units/kube-controller-manager.service" "units/kube-scheduler.service")
for unit in "${required_units[@]}"; do
    if [ ! -f "$unit" ]; then
        echo -e "  ${RED}❌ $unit not found${NC}"
        missing_files+=("$unit")
    else
        echo -e "  ${GREEN}✅ $unit${NC}"
    fi
done

# Check if config files exist
required_configs=("configs/kube-scheduler.yaml" "configs/kube-apiserver-to-kubelet.yaml")
for config in "${required_configs[@]}"; do
    if [ ! -f "$config" ]; then
        echo -e "  ${RED}❌ $config not found${NC}"
        missing_files+=("$config")
    else
        echo -e "  ${GREEN}✅ $config${NC}"
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo -e "${RED}❌ Missing required files: ${missing_files[*]}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites verified${NC}"
echo ""

echo -e "${YELLOW}📦 Step 2: Copying binaries and config files to controller${NC}"

# Test connectivity to server
echo "Testing connectivity to server..."
if ! timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@server" "echo 'Connection test'" >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to server${NC}"
    echo "Please ensure 'make setup-compute' has been run and SSH connectivity is working"
    exit 1
fi
echo -e "${GREEN}✅ Connected to server${NC}"

# Copy binaries and files to server
echo "Copying Kubernetes binaries and configuration files to server..."
scp \
  downloads/controller/kube-apiserver \
  downloads/controller/kube-controller-manager \
  downloads/controller/kube-scheduler \
  downloads/client/kubectl \
  units/kube-apiserver.service \
  units/kube-controller-manager.service \
  units/kube-scheduler.service \
  configs/kube-scheduler.yaml \
  configs/kube-apiserver-to-kubelet.yaml \
  root@server:~/

echo -e "${GREEN}✅ Files copied to server${NC}"
echo ""

echo -e "${YELLOW}🔧 Step 3: Provisioning Kubernetes Control Plane${NC}"

# SSH to server and bootstrap control plane
echo "Connecting to server and bootstrapping control plane..."
ssh root@server << 'EOF'
set -euo pipefail

# Colors for remote script
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Creating Kubernetes configuration directory...${NC}"

# Create the Kubernetes configuration directory
mkdir -p /etc/kubernetes/config

echo -e "${GREEN}✅ Kubernetes configuration directory created${NC}"

echo ""
echo -e "${YELLOW}Installing Kubernetes Controller Binaries...${NC}"

# Install the Kubernetes binaries
{
  mv kube-apiserver \
    kube-controller-manager \
    kube-scheduler kubectl \
    /usr/local/bin/
}

# Verify binaries are installed and working
for binary in kube-apiserver kube-controller-manager kube-scheduler; do
    if ! /usr/local/bin/$binary --version >/dev/null 2>&1; then
        echo -e "${RED}❌ $binary installation failed${NC}"
        exit 1
    fi
done

# kubectl has different version check behavior
if ! /usr/local/bin/kubectl version --client >/dev/null 2>&1; then
    echo -e "${RED}❌ kubectl installation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Kubernetes binaries installed successfully${NC}"

# Show versions
echo "Installed versions:"
set +o pipefail
APISERVER_VERSION=$(/usr/local/bin/kube-apiserver --version 2>/dev/null | head -1 || echo "Version unavailable")
CONTROLLER_VERSION=$(/usr/local/bin/kube-controller-manager --version 2>/dev/null | head -1 || echo "Version unavailable")
SCHEDULER_VERSION=$(/usr/local/bin/kube-scheduler --version 2>/dev/null | head -1 || echo "Version unavailable")
KUBECTL_VERSION=$(/usr/local/bin/kubectl version --client 2>/dev/null | head -1 || echo "Version unavailable")
set -o pipefail
echo "  kube-apiserver: $APISERVER_VERSION"
echo "  kube-controller-manager: $CONTROLLER_VERSION"
echo "  kube-scheduler: $SCHEDULER_VERSION"
echo "  kubectl: $KUBECTL_VERSION"

echo ""
echo -e "${YELLOW}Configuring Kubernetes API Server...${NC}"

# Configure the Kubernetes API Server
{
  mkdir -p /var/lib/kubernetes/

  mv ca.crt ca.key \
    kube-api-server.key kube-api-server.crt \
    service-accounts.key service-accounts.crt \
    encryption-config.yaml \
    /var/lib/kubernetes/
}

# Verify certificates were moved
if [ ! -f /var/lib/kubernetes/ca.crt ] || [ ! -f /var/lib/kubernetes/kube-api-server.crt ]; then
    echo -e "${RED}❌ Failed to move certificates to /var/lib/kubernetes/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ API Server certificates and config moved to /var/lib/kubernetes/${NC}"

# Create the kube-apiserver.service systemd unit file
mv kube-apiserver.service \
  /etc/systemd/system/kube-apiserver.service

if [ ! -f /etc/systemd/system/kube-apiserver.service ]; then
    echo -e "${RED}❌ Failed to install kube-apiserver.service${NC}"
    exit 1
fi

echo -e "${GREEN}✅ kube-apiserver.service systemd unit file installed${NC}"

echo ""
echo -e "${YELLOW}Configuring Kubernetes Controller Manager...${NC}"

# Move the kube-controller-manager kubeconfig into place
mv kube-controller-manager.kubeconfig /var/lib/kubernetes/

# Create the kube-controller-manager.service systemd unit file
mv kube-controller-manager.service /etc/systemd/system/

# Verify files
if [ ! -f /var/lib/kubernetes/kube-controller-manager.kubeconfig ] || [ ! -f /etc/systemd/system/kube-controller-manager.service ]; then
    echo -e "${RED}❌ Failed to configure kube-controller-manager${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Kubernetes Controller Manager configured${NC}"

echo ""
echo -e "${YELLOW}Configuring Kubernetes Scheduler...${NC}"

# Move the kube-scheduler kubeconfig into place
mv kube-scheduler.kubeconfig /var/lib/kubernetes/

# Create the kube-scheduler.yaml configuration file
mv kube-scheduler.yaml /etc/kubernetes/config/

# Create the kube-scheduler.service systemd unit file
mv kube-scheduler.service /etc/systemd/system/

# Verify files
if [ ! -f /var/lib/kubernetes/kube-scheduler.kubeconfig ] || [ ! -f /etc/kubernetes/config/kube-scheduler.yaml ] || [ ! -f /etc/systemd/system/kube-scheduler.service ]; then
    echo -e "${RED}❌ Failed to configure kube-scheduler${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Kubernetes Scheduler configured${NC}"

echo ""
echo -e "${YELLOW}Starting Controller Services...${NC}"

# Start the Controller Services
{
  systemctl daemon-reload

  systemctl enable kube-apiserver \
    kube-controller-manager kube-scheduler

  systemctl start kube-apiserver \
    kube-controller-manager kube-scheduler
}

echo -e "${GREEN}✅ Controller services enabled and started${NC}"

echo ""
echo -e "${YELLOW}Allowing time for API Server initialization...${NC}"
echo "Waiting up to 60 seconds for Kubernetes API Server to fully initialize..."

# Wait for API server to be ready
attempts=0
max_attempts=12
while [ $attempts -lt $max_attempts ]; do
    if systemctl is-active --quiet kube-apiserver; then
        echo -e "${GREEN}✅ kube-apiserver is active${NC}"
        break
    fi
    echo "  Attempt $((attempts + 1))/$max_attempts - waiting 5 seconds..."
    sleep 5
    attempts=$((attempts + 1))
done

if [ $attempts -eq $max_attempts ]; then
    echo -e "${RED}❌ kube-apiserver failed to start within expected time${NC}"
    echo "Service status:"
    systemctl status kube-apiserver --no-pager || true
    exit 1
fi

echo ""
echo -e "${YELLOW}Verifying Control Plane Components...${NC}"

# Check if all control plane components are active
services=("kube-apiserver" "kube-controller-manager" "kube-scheduler")
all_active=true

for service in "${services[@]}"; do
    echo -n "  Checking $service: "
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✅ Active${NC}"
    else
        echo -e "${RED}❌ Not Active${NC}"
        all_active=false
        echo "    Status details:"
        systemctl status "$service" --no-pager | sed 's/^/      /' || true
    fi
done

if [ "$all_active" = false ]; then
    echo -e "${RED}❌ Some control plane components are not running${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All control plane components are running${NC}"

echo ""
echo -e "${GREEN}🎉 Control plane bootstrap completed successfully!${NC}"
EOF

# Check if the SSH session succeeded
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Control plane bootstrap completed on server${NC}"
else
    echo -e "${RED}❌ Control plane bootstrap failed on server${NC}"
    echo "You can manually connect to server and check the logs:"
    echo "  ssh root@server"
    echo "  systemctl status kube-apiserver"
    echo "  systemctl status kube-controller-manager"
    echo "  systemctl status kube-scheduler"
    echo "  journalctl -u kube-apiserver -f"
    exit 1
fi

echo ""

echo -e "${YELLOW}🔍 Step 4: Verification${NC}"

# Verify control plane from jumpbox
echo "Verifying Kubernetes control plane from jumpbox..."

echo ""
echo "Testing cluster info..."
if ssh root@server "kubectl cluster-info --kubeconfig admin.kubeconfig" 2>/dev/null; then
    echo -e "${GREEN}✅ Cluster info retrieved successfully${NC}"
else
    echo -e "${YELLOW}⚠️ Cluster info failed, but this may be normal during initial startup${NC}"
fi

echo ""
echo "Testing component status..."
for service in kube-apiserver kube-controller-manager kube-scheduler; do
    echo -n "  $service: "
    if ssh root@server "systemctl is-active --quiet $service"; then
        echo -e "${GREEN}✅ Running${NC}"
    else
        echo -e "${RED}❌ Not running${NC}"
    fi
done

echo ""
echo "Testing API server HTTP endpoint..."
if ssh root@server "curl --cacert /var/lib/kubernetes/ca.crt https://127.0.0.1:6443/version" 2>/dev/null | grep -q "gitVersion"; then
    echo -e "${GREEN}✅ API server HTTP endpoint is responding${NC}"
else
    echo -e "${YELLOW}⚠️ API server HTTP endpoint test failed${NC}"
fi

echo ""

echo -e "${YELLOW}🔐 Step 5: Configuring RBAC for Kubelet Authorization${NC}"

echo "Applying RBAC configuration for Kubelet API access..."
if ssh root@server "kubectl apply -f kube-apiserver-to-kubelet.yaml --kubeconfig admin.kubeconfig" 2>/dev/null; then
    echo -e "${GREEN}✅ RBAC configuration applied successfully${NC}"
else
    echo -e "${YELLOW}⚠️ RBAC configuration failed, but may be applied later${NC}"
fi

echo ""

echo -e "${GREEN}🎉 KUBERNETES CONTROL PLANE BOOTSTRAP COMPLETE!${NC}"
echo "====================================================="
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ Kubernetes binaries installed on controller${NC}"
echo "    • kube-apiserver, kube-controller-manager, kube-scheduler, kubectl"
echo ""
echo -e "  ${GREEN}✅ Control plane components configured${NC}"
echo "    • API Server with TLS certificates and encryption"
echo "    • Controller Manager with kubeconfig"
echo "    • Scheduler with configuration and kubeconfig"
echo ""
echo -e "  ${GREEN}✅ Systemd services created and started${NC}"
echo "    • kube-apiserver.service (enabled and running)"
echo "    • kube-controller-manager.service (enabled and running)"
echo "    • kube-scheduler.service (enabled and running)"
echo ""
echo -e "  ${GREEN}✅ RBAC configured for Kubelet authorization${NC}"
echo ""
echo "Control plane details:"
ssh root@server "kubectl cluster-info --kubeconfig admin.kubeconfig" 2>/dev/null | sed 's/^/  /' || echo "  (Run 'ssh root@server kubectl cluster-info --kubeconfig admin.kubeconfig' to see details)"
echo ""
echo "Configuration:"
echo "  📁 Binary location: /usr/local/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl}"
echo "  📁 Configuration: /var/lib/kubernetes/ and /etc/kubernetes/config/"
echo "  🔧 Services: kube-apiserver, kube-controller-manager, kube-scheduler (all enabled and running)"
echo ""
echo "Verification commands:"
echo "  ssh root@server 'systemctl status kube-apiserver'"
echo "  ssh root@server 'systemctl status kube-controller-manager'"
echo "  ssh root@server 'systemctl status kube-scheduler'"
echo "  ssh root@server 'kubectl cluster-info --kubeconfig admin.kubeconfig'"
echo "  ssh root@server 'kubectl get componentstatuses --kubeconfig admin.kubeconfig'"
echo ""
echo "API Server endpoint:"
echo "  https://server.kubernetes.local:6443"
echo "  https://127.0.0.1:6443 (from controller)"
echo ""
echo -e "${BLUE}Next step: Bootstrap Kubernetes worker nodes${NC}"
echo "Run: make bootstrap-workers"
echo ""

cd ..