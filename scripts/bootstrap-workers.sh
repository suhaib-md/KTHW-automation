#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}👷 Kubernetes the Hard Way - Bootstrap Worker Nodes${NC}"
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

# Check if machines.txt exists
if [ ! -f "machines.txt" ]; then
    echo -e "${RED}❌ machines.txt not found. Please run 'make setup-compute' first.${NC}"
    exit 1
fi

# Check if downloads directory exists
if [ ! -d "downloads" ]; then
    echo -e "${RED}❌ downloads directory not found${NC}"
    echo "Please ensure the kubernetes-the-hard-way repository is properly cloned"
    exit 1
fi

# Check if worker binaries exist
required_binaries=("downloads/worker/crictl" "downloads/worker/kube-proxy" "downloads/worker/kubelet" "downloads/worker/runc")
missing_files=()

for binary in "${required_binaries[@]}"; do
    if [ ! -f "$binary" ]; then
        echo -e "  ${RED}❌ $binary not found${NC}"
        missing_files+=("$binary")
    else
        echo -e "  ${GREEN}✅ $binary${NC}"
    fi
done

# Check for client binaries
if [ ! -f "downloads/client/kubectl" ]; then
    echo -e "  ${RED}❌ downloads/client/kubectl not found${NC}"
    missing_files+=("downloads/client/kubectl")
else
    echo -e "  ${GREEN}✅ downloads/client/kubectl${NC}"
fi

# Check for CNI plugins
if [ ! -d "downloads/cni-plugins" ]; then
    echo -e "  ${RED}❌ downloads/cni-plugins directory not found${NC}"
    missing_files+=("downloads/cni-plugins")
else
    echo -e "  ${GREEN}✅ downloads/cni-plugins${NC}"
fi

# Check for containerd binaries
containerd_binaries=("downloads/worker/containerd" "downloads/worker/containerd-shim-runc-v2" "downloads/worker/containerd-stress")
for binary in "${containerd_binaries[@]}"; do
    if [ ! -f "$binary" ]; then
        echo -e "  ${RED}❌ $binary not found${NC}"
        missing_files+=("$binary")
    else
        echo -e "  ${GREEN}✅ $binary${NC}"
    fi
done

# Check for config files
required_configs=("configs/99-loopback.conf" "configs/containerd-config.toml" "configs/kube-proxy-config.yaml")
for config in "${required_configs[@]}"; do
    if [ ! -f "$config" ]; then
        echo -e "  ${RED}❌ $config not found${NC}"
        missing_files+=("$config")
    else
        echo -e "  ${GREEN}✅ $config${NC}"
    fi
done

# Check for systemd unit files
required_units=("units/containerd.service" "units/kubelet.service" "units/kube-proxy.service")
for unit in "${required_units[@]}"; do
    if [ ! -f "$unit" ]; then
        echo -e "  ${RED}❌ $unit not found${NC}"
        missing_files+=("$unit")
    else
        echo -e "  ${GREEN}✅ $unit${NC}"
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo -e "${RED}❌ Missing required files: ${missing_files[*]}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites verified${NC}"
echo ""

echo -e "${YELLOW}📦 Step 2: Copying binaries and configuration files to workers${NC}"

# Test connectivity to workers
echo "Testing connectivity to worker nodes..."
for host in node-0 node-1; do
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$host" "echo 'Connection test'" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $host - Connected${NC}"
    else
        echo -e "  ${RED}❌ $host - Connection failed${NC}"
        echo "Cannot proceed with worker bootstrap. Check connectivity."
        exit 1
    fi
done
echo ""

# Copy bridge configuration and kubelet config to each worker
for HOST in node-0 node-1; do
    echo "  → Preparing configuration for $HOST..."
    
    # Get subnet from machines.txt
    SUBNET=$(grep ${HOST} machines.txt | cut -d " " -f 4)
    echo "    Using subnet: $SUBNET"
    
    # Generate 10-bridge.conf for this host
    sed "s|SUBNET|$SUBNET|g" configs/10-bridge.conf > 10-bridge.conf
    
    # Generate kubelet-config.yaml for this host
    sed "s|SUBNET|$SUBNET|g" configs/kubelet-config.yaml > kubelet-config.yaml
    
    # Copy host-specific configs
    scp 10-bridge.conf kubelet-config.yaml root@${HOST}:~/
    
    echo -e "    ${GREEN}✅ Host-specific configs copied to $HOST${NC}"
done

echo ""

# Copy binaries and configs to all workers
for HOST in node-0 node-1; do
    echo "  → Copying binaries and configs to $HOST..."
    
    # Copy worker binaries
    scp \
      downloads/worker/* \
      downloads/client/kubectl \
      configs/99-loopback.conf \
      configs/containerd-config.toml \
      configs/kube-proxy-config.yaml \
      units/containerd.service \
      units/kubelet.service \
      units/kube-proxy.service \
      root@${HOST}:~/
    
    echo -e "    ${GREEN}✅ Binaries and configs copied to $HOST${NC}"
done

echo ""

# Copy CNI plugins
for HOST in node-0 node-1; do
    echo "  → Creating CNI directory and copying plugins to $HOST..."
    
    # Create cni-plugins directory and copy files
    ssh root@${HOST} "mkdir -p ~/cni-plugins"
    scp downloads/cni-plugins/* root@${HOST}:~/cni-plugins/
    
    echo -e "    ${GREEN}✅ CNI plugins copied to $HOST${NC}"
done

echo ""

echo -e "${YELLOW}🔧 Step 3: Bootstrapping worker nodes${NC}"

# Bootstrap each worker node
for HOST in node-0 node-1; do
    echo "Processing worker node: $HOST"
    echo "==============================="
    
    ssh root@${HOST} << 'EOF'
set -euo pipefail

# Colors for remote script
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Installing OS dependencies...${NC}"

# Install the OS dependencies
{
  apt-get update
  apt-get -y install socat conntrack ipset kmod
}

echo -e "${GREEN}✅ OS dependencies installed${NC}"

echo ""
echo -e "${YELLOW}Disabling swap...${NC}"

# Check if swap is enabled
if swapon --show | grep -q "/"; then
    echo "Swap is enabled, disabling it..."
    swapoff -a
    echo -e "${GREEN}✅ Swap disabled${NC}"
else
    echo -e "${GREEN}✅ Swap is already disabled${NC}"
fi

echo ""
echo -e "${YELLOW}Creating installation directories...${NC}"

# Create the installation directories
mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

echo -e "${GREEN}✅ Installation directories created${NC}"

echo ""
echo -e "${YELLOW}Installing worker binaries...${NC}"

# Install the worker binaries
{
  mv crictl kube-proxy kubelet runc \
    /usr/local/bin/
  mv containerd containerd-shim-runc-v2 containerd-stress /bin/
  mv cni-plugins/* /opt/cni/bin/
}

# Set executable permissions
chmod +x /usr/local/bin/{crictl,kube-proxy,kubelet,runc}
chmod +x /bin/{containerd,containerd-shim-runc-v2,containerd-stress}
chmod +x /opt/cni/bin/*

echo -e "${GREEN}✅ Worker binaries installed${NC}"

# Verify key binaries
echo "Verifying binary installations..."
for binary in crictl kube-proxy kubelet runc; do
    if command -v $binary >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $binary${NC}"
    else
        echo -e "  ${RED}❌ $binary${NC}"
    fi
done

echo ""
echo -e "${YELLOW}Configuring CNI Networking...${NC}"

# Create the bridge network configuration file
mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/

echo -e "${GREEN}✅ CNI configuration files moved${NC}"

# Configure br-netfilter kernel module
{
  modprobe br-netfilter
  echo "br-netfilter" >> /etc/modules-load.d/modules.conf
}

echo -e "${GREEN}✅ br-netfilter module loaded${NC}"

# Configure sysctl for iptables
{
  echo "net.bridge.bridge-nf-call-iptables = 1" \
    >> /etc/sysctl.d/kubernetes.conf
  echo "net.bridge.bridge-nf-call-ip6tables = 1" \
    >> /etc/sysctl.d/kubernetes.conf
  sysctl -p /etc/sysctl.d/kubernetes.conf
}

echo -e "${GREEN}✅ Network configuration applied${NC}"

echo ""
echo -e "${YELLOW}Configuring containerd...${NC}"

# Install the containerd configuration files
{
  mkdir -p /etc/containerd/
  mv containerd-config.toml /etc/containerd/config.toml
  mv containerd.service /etc/systemd/system/
}

echo -e "${GREEN}✅ containerd configured${NC}"

echo ""
echo -e "${YELLOW}Configuring the Kubelet...${NC}"

# Configure the Kubelet
{
  mv kubelet-config.yaml /var/lib/kubelet/
  mv kubelet.service /etc/systemd/system/
}

echo -e "${GREEN}✅ Kubelet configured${NC}"

echo ""
echo -e "${YELLOW}Configuring the Kubernetes Proxy...${NC}"

# Configure the Kubernetes Proxy
{
  mv kube-proxy-config.yaml /var/lib/kube-proxy/
  mv kube-proxy.service /etc/systemd/system/
}

echo -e "${GREEN}✅ Kubernetes Proxy configured${NC}"

echo ""
echo -e "${YELLOW}Starting Worker Services...${NC}"

# Start the Worker Services
{
  systemctl daemon-reload
  systemctl enable containerd kubelet kube-proxy
  systemctl start containerd kubelet kube-proxy
}

echo -e "${GREEN}✅ Worker services enabled and started${NC}"

echo ""
echo -e "${YELLOW}Verifying services...${NC}"

# Check if services are active
services=("containerd" "kubelet" "kube-proxy")
all_active=true

for service in "${services[@]}"; do
    echo -n "  Checking $service: "
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✅ Active${NC}"
    else
        echo -e "${RED}❌ Not Active${NC}"
        all_active=false
    fi
done

if [ "$all_active" = true ]; then
    echo -e "${GREEN}✅ All worker services are running${NC}"
else
    echo -e "${RED}❌ Some services are not running${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Worker node bootstrap completed!${NC}"
EOF

    # Check if the SSH session succeeded
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Worker bootstrap completed on $HOST${NC}"
    else
        echo -e "${RED}❌ Worker bootstrap failed on $HOST${NC}"
        exit 1
    fi
    echo ""
done

echo -e "${YELLOW}🔍 Step 4: Verification${NC}"

# Verify workers from jumpbox
echo "Verifying worker node status from controller..."
echo ""

# Check if workers are registered
echo "Checking registered Kubernetes nodes..."
if ssh root@server "kubectl get nodes --kubeconfig admin.kubeconfig" 2>/dev/null; then
    echo -e "${GREEN}✅ Worker nodes are registered with the cluster${NC}"
else
    echo -e "${YELLOW}⚠️ Node registration check failed (may take a few minutes)${NC}"
fi

echo ""

# Check worker services status
echo "Verifying worker services on each node..."
for HOST in node-0 node-1; do
    echo "  → Checking services on $HOST..."
    
    for service in containerd kubelet kube-proxy; do
        echo -n "    $service: "
        if ssh root@${HOST} "systemctl is-active --quiet $service"; then
            echo -e "${GREEN}✅ Running${NC}"
        else
            echo -e "${RED}❌ Not running${NC}"
        fi
    done
done

echo ""

echo -e "${GREEN}🎉 KUBERNETES WORKER NODES BOOTSTRAP COMPLETE!${NC}"
echo "===================================================="
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ OS dependencies installed on both worker nodes${NC}"
echo "    • socat, conntrack, ipset, kmod"
echo ""
echo -e "  ${GREEN}✅ Worker binaries installed:${NC}"
echo "    • crictl, kube-proxy, kubelet, runc (in /usr/local/bin/)"
echo "    • containerd, containerd-shim-runc-v2, containerd-stress (in /bin/)"
echo "    • CNI plugins (in /opt/cni/bin/)"
echo ""
echo -e "  ${GREEN}✅ Network configuration applied:${NC}"
echo "    • CNI bridge network configuration"
echo "    • br-netfilter kernel module loaded"
echo "    • iptables bridge configuration"
echo ""
echo -e "  ${GREEN}✅ Services configured and started:${NC}"
echo "    • containerd.service (container runtime)"
echo "    • kubelet.service (Kubernetes node agent)"
echo "    • kube-proxy.service (Kubernetes network proxy)"
echo ""
echo "Node registration status:"
ssh root@server "kubectl get nodes --kubeconfig admin.kubeconfig" 2>/dev/null | sed 's/^/  /' || echo "  (Run 'ssh root@server kubectl get nodes --kubeconfig admin.kubeconfig' to check)"
echo ""
echo "Configuration paths:"
echo "  📁 Binaries: /usr/local/bin/, /bin/, /opt/cni/bin/"
echo "  📁 CNI configs: /etc/cni/net.d/"
echo "  📁 Kubelet config: /var/lib/kubelet/"
echo "  📁 Kube-proxy config: /var/lib/kube-proxy/"
echo ""
echo "Verification commands:"
echo "  ssh root@node-0 'systemctl status kubelet'"
echo "  ssh root@node-1 'systemctl status kubelet'"
echo "  ssh root@server 'kubectl get nodes --kubeconfig admin.kubeconfig'"
echo ""
echo -e "${BLUE}Next step: Configure kubectl for remote access${NC}"
echo "Run: make configure-kubectl"
echo ""

cd ..