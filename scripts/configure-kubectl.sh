#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🎛️  Kubernetes the Hard Way - Configure kubectl for Remote Access${NC}"
echo "=================================================================="
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

# Check if required certificate files exist
required_files=("ca.crt" "admin.crt" "admin.key")
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
    exit 1
fi

# Check if control plane is running
echo ""
echo "Checking if Kubernetes control plane is accessible..."
if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@server" "systemctl is-active --quiet kube-apiserver" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Control plane is running${NC}"
else
    echo -e "${RED}❌ Control plane is not accessible${NC}"
    echo "Please ensure the control plane is bootstrapped:"
    echo "  make bootstrap-etcd"
    echo "  make bootstrap-control-plane"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites verified${NC}"
echo ""

echo -e "${YELLOW}🌐 Step 2: Testing API Server connectivity${NC}"

echo "Testing API Server endpoint..."
if curl --cacert ca.crt --connect-timeout 10 -s https://server.kubernetes.local:6443/version | grep -q "gitVersion"; then
    echo -e "${GREEN}✅ API Server is responding${NC}"
    
    echo ""
    echo "API Server version information:"
    curl --cacert ca.crt -s https://server.kubernetes.local:6443/version | python3 -m json.tool 2>/dev/null || curl --cacert ca.crt -s https://server.kubernetes.local:6443/version
    echo ""
else
    echo -e "${RED}❌ API Server is not responding${NC}"
    echo "Debugging information:"
    echo "  Testing basic connectivity to server..."
    if ping -c 1 server.kubernetes.local >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ server.kubernetes.local is reachable${NC}"
    else
        echo -e "  ${RED}❌ server.kubernetes.local is not reachable${NC}"
        echo "  Check /etc/hosts configuration"
    fi
    
    echo "  Testing API Server service status..."
    ssh root@server "systemctl status kube-apiserver --no-pager" || true
    exit 1
fi

echo ""

echo -e "${YELLOW}🔧 Step 3: Creating kubectl configuration directory${NC}"

# Create .kube directory if it doesn't exist
if [ ! -d "$HOME/.kube" ]; then
    mkdir -p "$HOME/.kube"
    echo -e "${GREEN}✅ Created $HOME/.kube directory${NC}"
else
    echo -e "${GREEN}✅ $HOME/.kube directory already exists${NC}"
fi

# Backup existing kubeconfig if it exists
if [ -f "$HOME/.kube/config" ]; then
    echo "Backing up existing kubeconfig..."
    cp "$HOME/.kube/config" "$HOME/.kube/config.backup.$(date +%Y%m%d-%H%M%S)"
    echo -e "${GREEN}✅ Existing kubeconfig backed up${NC}"
fi

echo ""

echo -e "${YELLOW}🔑 Step 4: Generating kubectl configuration for remote access${NC}"

echo "Configuring kubectl for the admin user..."

# Set cluster configuration (pointing to external endpoint)
echo "  → Setting cluster configuration..."
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443

echo -e "    ${GREEN}✅ Cluster configuration set${NC}"

# Set credentials
echo "  → Setting user credentials..."
kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true

echo -e "    ${GREEN}✅ User credentials set${NC}"

# Set context
echo "  → Setting context..."
kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

echo -e "    ${GREEN}✅ Context set${NC}"

# Use context
echo "  → Using context..."
kubectl config use-context kubernetes-the-hard-way

echo -e "    ${GREEN}✅ Context activated${NC}"

echo ""
echo -e "${GREEN}✅ kubectl configuration completed${NC}"
echo ""

echo -e "${YELLOW}🔍 Step 5: Verification${NC}"

# Test kubectl configuration
echo "Testing kubectl configuration..."

echo ""
echo "1. Checking kubectl version (client and server)..."
if kubectl version --short 2>/dev/null; then
    echo -e "${GREEN}✅ kubectl version check successful${NC}"
elif kubectl version 2>/dev/null; then
    echo -e "${GREEN}✅ kubectl version check successful${NC}"
else
    echo -e "${RED}❌ kubectl version check failed${NC}"
    exit 1
fi

echo ""
echo "2. Checking cluster info..."
if kubectl cluster-info 2>/dev/null; then
    echo -e "${GREEN}✅ Cluster info retrieved successfully${NC}"
else
    echo -e "${YELLOW}⚠️ Cluster info check had issues, but may still be functional${NC}"
fi

echo ""
echo "3. Listing nodes in the cluster..."
if kubectl get nodes 2>/dev/null; then
    echo -e "${GREEN}✅ Node listing successful${NC}"
    
    # Count nodes
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    echo "Found $node_count worker node(s)"
    
    # Check node status
    echo ""
    echo "Node status details:"
    kubectl get nodes -o wide 2>/dev/null || kubectl get nodes 2>/dev/null
    
else
    echo -e "${YELLOW}⚠️ Node listing failed - workers may not be fully ready yet${NC}"
    echo "This is normal if worker nodes are still joining the cluster"
fi

echo ""
echo "4. Testing basic cluster access..."
if kubectl get namespaces >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Cluster access successful${NC}"
    echo "Available namespaces:"
    kubectl get namespaces
else
    echo -e "${RED}❌ Cluster access failed${NC}"
    exit 1
fi

echo ""

echo -e "${YELLOW}📊 Step 6: Configuration summary${NC}"

echo "Current kubectl configuration:"
echo "  Context: $(kubectl config current-context)"
echo "  Cluster: $(kubectl config get-clusters | grep -v NAME | head -1)"
echo "  User: $(kubectl config view --minify -o jsonpath='{.contexts[0].context.user}')"
echo "  Server: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
echo ""

echo "Configuration file location:"
echo "  $HOME/.kube/config"
echo ""

# Show kubeconfig file size and basic info
if [ -f "$HOME/.kube/config" ]; then
    config_size=$(wc -c < "$HOME/.kube/config")
    echo "Configuration file size: $config_size bytes"
    
    echo ""
    echo "Kubeconfig structure:"
    kubectl config view --flatten=false | head -20
    echo "..."
fi

echo ""

echo -e "${GREEN}🎉 KUBECTL REMOTE ACCESS CONFIGURATION COMPLETE!${NC}"
echo "======================================================="
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ kubectl configured for remote access to Kubernetes cluster${NC}"
echo -e "  ${GREEN}✅ Admin user credentials embedded in kubeconfig${NC}"
echo -e "  ${GREEN}✅ Cluster certificates embedded for secure communication${NC}"
echo -e "  ${GREEN}✅ Context set to kubernetes-the-hard-way${NC}"
echo -e "  ${GREEN}✅ Configuration verified with cluster connectivity${NC}"
echo ""
echo "Remote access details:"
echo "  • Cluster endpoint: https://server.kubernetes.local:6443"
echo "  • Authentication: TLS client certificates (admin user)"
echo "  • Context: kubernetes-the-hard-way"
echo ""
echo "You can now use kubectl commands directly:"
echo "  kubectl get nodes"
echo "  kubectl get pods --all-namespaces"
echo "  kubectl cluster-info"
echo "  kubectl version"
echo ""
echo "Useful kubectl commands:"
echo "  kubectl config view                    # View current configuration"
echo "  kubectl config current-context        # Show current context"
echo "  kubectl get componentstatuses         # Check control plane health"
echo "  kubectl get nodes -o wide             # Detailed node information"
echo ""
echo -e "${BLUE}Next step: Provision pod network routes${NC}"
echo "Run: make setup-networking"
echo ""

cd ..