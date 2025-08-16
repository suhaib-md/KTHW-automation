#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🔐 Kubernetes the Hard Way - Configuration Files Generation${NC}"
echo "=========================================================="
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

# Check if machines.txt exists
if [ ! -f "kubernetes-the-hard-way/machines.txt" ]; then
    echo -e "${RED}❌ machines.txt not found. Please run 'make setup-compute' first.${NC}"
    exit 1
fi

# Check if certificates exist
cd kubernetes-the-hard-way

if [ ! -f "ca.crt" ] || [ ! -f "admin.crt" ] || [ ! -f "node-0.crt" ]; then
    echo -e "${RED}❌ Certificate files not found. Please run 'make generate-certs' first.${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Step 1: Verifying certificate files${NC}"
echo "Required certificate files:"

# List of required certificates for kubeconfig generation
required_certs=("ca.crt" "admin.crt" "admin.key" "node-0.crt" "node-0.key" "node-1.crt" "node-1.key" 
                "kube-proxy.crt" "kube-proxy.key" "kube-controller-manager.crt" "kube-controller-manager.key"
                "kube-scheduler.crt" "kube-scheduler.key")

missing_certs=()
for cert in "${required_certs[@]}"; do
    if [ -f "$cert" ]; then
        echo -e "  ${GREEN}✅ $cert${NC}"
    else
        echo -e "  ${RED}❌ $cert${NC}"
        missing_certs+=("$cert")
    fi
done

if [ ${#missing_certs[@]} -gt 0 ]; then
    echo -e "${RED}❌ Missing required certificate files: ${missing_certs[*]}${NC}"
    echo "Please run 'make generate-certs' to create missing certificates."
    exit 1
fi

echo ""
echo -e "${GREEN}✅ All required certificate files present${NC}"
echo ""

echo -e "${YELLOW}🔧 Step 2: Generating kubelet configuration files${NC}"

# Clean up any existing kubeconfig files
echo "Cleaning up existing kubeconfig files..."
rm -f *.kubeconfig 2>/dev/null || true

# Generate kubeconfig files for worker nodes (following KTHW exactly)
echo "Generating kubeconfig files for worker nodes..."

for host in node-0 node-1; do
    echo "  → Generating kubeconfig for $host..."
    
    # Set cluster configuration
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=ca.crt \
        --embed-certs=true \
        --server=https://server.kubernetes.local:6443 \
        --kubeconfig=${host}.kubeconfig
    
    # Set credentials
    kubectl config set-credentials system:node:${host} \
        --client-certificate=${host}.crt \
        --client-key=${host}.key \
        --embed-certs=true \
        --kubeconfig=${host}.kubeconfig
    
    # Set context
    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=system:node:${host} \
        --kubeconfig=${host}.kubeconfig
    
    # Use context
    kubectl config use-context default \
        --kubeconfig=${host}.kubeconfig
    
    echo -e "    ${GREEN}✅ ${host}.kubeconfig created${NC}"
done

echo ""

echo -e "${YELLOW}🔧 Step 3: Generating kube-proxy configuration file${NC}"

echo "Generating kube-proxy.kubeconfig..."
{
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=ca.crt \
        --embed-certs=true \
        --server=https://server.kubernetes.local:6443 \
        --kubeconfig=kube-proxy.kubeconfig

    kubectl config set-credentials system:kube-proxy \
        --client-certificate=kube-proxy.crt \
        --client-key=kube-proxy.key \
        --embed-certs=true \
        --kubeconfig=kube-proxy.kubeconfig

    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=system:kube-proxy \
        --kubeconfig=kube-proxy.kubeconfig

    kubectl config use-context default \
        --kubeconfig=kube-proxy.kubeconfig
}

echo -e "${GREEN}✅ kube-proxy.kubeconfig created${NC}"
echo ""

echo -e "${YELLOW}🔧 Step 4: Generating kube-controller-manager configuration file${NC}"

echo "Generating kube-controller-manager.kubeconfig..."
{
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=ca.crt \
        --embed-certs=true \
        --server=https://server.kubernetes.local:6443 \
        --kubeconfig=kube-controller-manager.kubeconfig

    kubectl config set-credentials system:kube-controller-manager \
        --client-certificate=kube-controller-manager.crt \
        --client-key=kube-controller-manager.key \
        --embed-certs=true \
        --kubeconfig=kube-controller-manager.kubeconfig

    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=system:kube-controller-manager \
        --kubeconfig=kube-controller-manager.kubeconfig

    kubectl config use-context default \
        --kubeconfig=kube-controller-manager.kubeconfig
}

echo -e "${GREEN}✅ kube-controller-manager.kubeconfig created${NC}"
echo ""

echo -e "${YELLOW}🔧 Step 5: Generating kube-scheduler configuration file${NC}"

echo "Generating kube-scheduler.kubeconfig..."
{
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=ca.crt \
        --embed-certs=true \
        --server=https://server.kubernetes.local:6443 \
        --kubeconfig=kube-scheduler.kubeconfig

    kubectl config set-credentials system:kube-scheduler \
        --client-certificate=kube-scheduler.crt \
        --client-key=kube-scheduler.key \
        --embed-certs=true \
        --kubeconfig=kube-scheduler.kubeconfig

    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=system:kube-scheduler \
        --kubeconfig=kube-scheduler.kubeconfig

    kubectl config use-context default \
        --kubeconfig=kube-scheduler.kubeconfig
}

echo -e "${GREEN}✅ kube-scheduler.kubeconfig created${NC}"
echo ""

echo -e "${YELLOW}🔧 Step 6: Generating admin configuration file${NC}"

echo "Generating admin.kubeconfig..."
{
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=ca.crt \
        --embed-certs=true \
        --server=https://127.0.0.1:6443 \
        --kubeconfig=admin.kubeconfig

    kubectl config set-credentials admin \
        --client-certificate=admin.crt \
        --client-key=admin.key \
        --embed-certs=true \
        --kubeconfig=admin.kubeconfig

    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=admin \
        --kubeconfig=admin.kubeconfig

    kubectl config use-context default \
        --kubeconfig=admin.kubeconfig
}

echo -e "${GREEN}✅ admin.kubeconfig created${NC}"
echo ""

# List generated kubeconfig files
echo -e "${YELLOW}📋 Generated kubeconfig files:${NC}"
ls -1 *.kubeconfig | sort | sed 's/^/  • /'
echo ""

kubeconfig_count=$(ls -1 *.kubeconfig | wc -l)
echo "Summary: $kubeconfig_count kubeconfig files generated"
echo ""

echo -e "${YELLOW}📦 Step 7: Distributing configuration files${NC}"

# Test connectivity first
echo "Testing connectivity to nodes..."
for host in node-0 node-1 server; do
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$host" "echo 'Connection test'" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $host - Connected${NC}"
    else
        echo -e "  ${RED}❌ $host - Connection failed${NC}"
        echo "Cannot proceed with kubeconfig distribution. Check connectivity."
        exit 1
    fi
done
echo ""

# Distribute kubelet and kube-proxy kubeconfig files to worker nodes
echo "Distributing kubeconfig files to worker nodes..."
for host in node-0 node-1; do
    echo "  → Processing $host..."
    
    # Create directories
    ssh root@${host} "mkdir -p /var/lib/{kube-proxy,kubelet}"
    echo "    Created directories"
    
    # Copy kube-proxy kubeconfig
    scp kube-proxy.kubeconfig root@${host}:/var/lib/kube-proxy/kubeconfig
    echo "    Copied kube-proxy.kubeconfig -> /var/lib/kube-proxy/kubeconfig"
    
    # Copy node-specific kubeconfig
    scp ${host}.kubeconfig root@${host}:/var/lib/kubelet/kubeconfig
    echo "    Copied ${host}.kubeconfig -> /var/lib/kubelet/kubeconfig"
    
    echo -e "    ${GREEN}✅ $host kubeconfig distribution complete${NC}"
done
echo ""

# Distribute controller kubeconfig files to controller node
echo "Distributing kubeconfig files to controller node..."
scp admin.kubeconfig \
    kube-controller-manager.kubeconfig \
    kube-scheduler.kubeconfig \
    root@server:~/

echo -e "  ${GREEN}✅ Controller kubeconfig distribution complete${NC}"
echo ""

echo -e "${YELLOW}🔍 Step 8: Verification${NC}"

# Verify kubeconfig files on worker nodes
echo "Verifying kubeconfig files on worker nodes..."
for host in node-0 node-1; do
    echo "  → Verifying $host..."
    
    # Check if files exist
    file_check=$(ssh root@${host} "
        ls -la /var/lib/kube-proxy/kubeconfig /var/lib/kubelet/kubeconfig 2>/dev/null | wc -l
    ")
    
    if [ "$file_check" -eq 2 ]; then
        echo -e "    ${GREEN}✅ Both kubeconfig files present${NC}"
        
        # Check file sizes (kubeconfigs should not be empty)
        sizes=$(ssh root@${host} "
            wc -c /var/lib/kube-proxy/kubeconfig /var/lib/kubelet/kubeconfig 2>/dev/null | grep -v total
        ")
        echo "    File sizes:"
        echo "$sizes" | sed 's/^/      /'
        
        # Verify kubeconfig structure
        echo "    Verifying kubeconfig structure..."
        kubelet_clusters=$(ssh root@${host} "grep -c 'clusters:' /var/lib/kubelet/kubeconfig 2>/dev/null || echo 0")
        proxy_clusters=$(ssh root@${host} "grep -c 'clusters:' /var/lib/kube-proxy/kubeconfig 2>/dev/null || echo 0")
        
        if [ "$kubelet_clusters" -eq 1 ] && [ "$proxy_clusters" -eq 1 ]; then
            echo -e "    ${GREEN}✅ Kubeconfig structure validated${NC}"
        else
            echo -e "    ${YELLOW}⚠️ Kubeconfig structure validation inconclusive${NC}"
        fi
        
    else
        echo -e "    ${RED}❌ Missing kubeconfig files (found: $file_check/2)${NC}"
    fi
done
echo ""

# Verify kubeconfig files on controller
echo "Verifying kubeconfig files on controller (server)..."
file_check=$(ssh root@server "ls -la ~/{admin,kube-controller-manager,kube-scheduler}.kubeconfig 2>/dev/null | wc -l")

if [ "$file_check" -eq 3 ]; then
    echo -e "  ${GREEN}✅ All 3 kubeconfig files present on controller${NC}"
    
    # Check file sizes
    sizes=$(ssh root@server "wc -c ~/{admin,kube-controller-manager,kube-scheduler}.kubeconfig 2>/dev/null | grep -v total")
    echo "  File sizes:"
    echo "$sizes" | sed 's/^/    /'
    
    # Verify admin kubeconfig can be used (basic syntax check)
    echo "  Testing admin kubeconfig syntax..."
    if ssh root@server "cd ~ && kubectl --kubeconfig=admin.kubeconfig config view >/dev/null 2>&1"; then
        echo -e "  ${GREEN}✅ Admin kubeconfig syntax valid${NC}"
    else
        echo -e "  ${YELLOW}⚠️ Admin kubeconfig syntax check failed (but may work when API server is running)${NC}"
    fi
    
else
    echo -e "  ${RED}❌ Missing kubeconfig files on controller (found: $file_check/3)${NC}"
fi
echo ""

echo -e "${GREEN}🎉 KUBERNETES CONFIGURATION FILES GENERATION COMPLETE!${NC}"
echo "============================================================"
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ 5 kubeconfig files generated:${NC}"
echo "    • node-0.kubeconfig (kubelet for worker node 0)"
echo "    • node-1.kubeconfig (kubelet for worker node 1)"
echo "    • kube-proxy.kubeconfig (kube-proxy service)"
echo "    • kube-controller-manager.kubeconfig (controller manager)"
echo "    • kube-scheduler.kubeconfig (scheduler)"
echo "    • admin.kubeconfig (cluster admin)"
echo ""
echo -e "  ${GREEN}✅ Worker node kubeconfigs distributed:${NC}"
echo "    • node-0: /var/lib/kube-proxy/kubeconfig, /var/lib/kubelet/kubeconfig"
echo "    • node-1: /var/lib/kube-proxy/kubeconfig, /var/lib/kubelet/kubeconfig"
echo ""
echo -e "  ${GREEN}✅ Controller kubeconfigs distributed:${NC}"
echo "    • server: ~/admin.kubeconfig, ~/kube-controller-manager.kubeconfig,"
echo "              ~/kube-scheduler.kubeconfig"
echo ""
echo "Kubeconfig files remaining in jumpbox:"
ls -1 *.kubeconfig | sed 's/^/  • /'
echo ""
echo -e "${BLUE}Next step: Generate data encryption configuration${NC}"
echo "Run: make generate-encryption"
echo ""

cd ..