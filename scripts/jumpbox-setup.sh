#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🖥️  Kubernetes the Hard Way - Jumpbox Setup${NC}"
echo "=============================================="
echo "Setting up your WSL Debian environment as the jumpbox..."
echo ""

# Check if infrastructure is deployed
if [ ! -f terraform.tfstate ]; then
    echo -e "${RED}❌ No infrastructure found. Please run 'make deploy' first.${NC}"
    exit 1
fi

# Step 1: Update system and install required packages
echo -e "${YELLOW}📦 Step 1: Installing required packages...${NC}"
sudo apt-get update
sudo apt-get -y install wget curl vim openssl git jq socat conntrack ipset

echo -e "${GREEN}✅ Required packages installed${NC}"
echo ""

# Step 2: Clone the repository
echo -e "${YELLOW}📁 Step 2: Cloning kubernetes-the-hard-way repository...${NC}"
if [ ! -d "kubernetes-the-hard-way" ]; then
    git clone --depth 1 https://github.com/kelseyhightower/kubernetes-the-hard-way.git
    echo -e "${GREEN}✅ Repository cloned${NC}"
else
    echo -e "${GREEN}✅ Repository already exists${NC}"
    cd kubernetes-the-hard-way
    git pull
    cd ..
fi

cd kubernetes-the-hard-way
echo ""

# Step 3: Check architecture and show what will be downloaded
echo -e "${YELLOW}🔍 Step 3: Checking system architecture...${NC}"
ARCH=$(dpkg --print-architecture)
echo "Architecture: $ARCH"
echo ""
echo "Files to download:"
cat downloads-${ARCH}.txt
echo ""

# Step 4: Download binaries
echo -e "${YELLOW}⬇️  Step 4: Downloading Kubernetes binaries...${NC}"
echo "This may take several minutes depending on your internet connection..."

# Create downloads directory if it doesn't exist
mkdir -p downloads

# Download with progress
wget -q --show-progress \
  --https-only \
  --timestamping \
  -P downloads \
  -i downloads-${ARCH}.txt

echo -e "${GREEN}✅ Download complete${NC}"
echo ""

# Step 5: List downloaded files
echo "📋 Downloaded files:"
ls -lh downloads/*.gz downloads/*.tgz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""

# Step 6: Extract and organize binaries
echo -e "${YELLOW}📦 Step 6: Extracting and organizing binaries...${NC}"

# Create directories
mkdir -p downloads/{client,cni-plugins,controller,worker}

# Extract files with progress
echo "  Extracting crictl..."
tar -xf downloads/crictl-v1.32.0-linux-${ARCH}.tar.gz -C downloads/worker/

echo "  Extracting containerd..."
tar -xf downloads/containerd-2.1.0-beta.0-linux-${ARCH}.tar.gz \
  --strip-components 1 \
  -C downloads/worker/

echo "  Extracting CNI plugins..."
tar -xf downloads/cni-plugins-linux-${ARCH}-v1.6.2.tgz \
  -C downloads/cni-plugins/

echo "  Extracting etcd..."
tar -xf downloads/etcd-v3.6.0-rc.3-linux-${ARCH}.tar.gz \
  -C downloads/ \
  --strip-components 1 \
  etcd-v3.6.0-rc.3-linux-${ARCH}/etcdctl \
  etcd-v3.6.0-rc.3-linux-${ARCH}/etcd

# Move binaries to appropriate directories
echo "  Organizing binaries..."
mv downloads/{etcdctl,kubectl} downloads/client/ 2>/dev/null || true
mv downloads/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler} downloads/controller/ 2>/dev/null || true
mv downloads/{kubelet,kube-proxy} downloads/worker/ 2>/dev/null || true
mv downloads/runc.${ARCH} downloads/worker/runc 2>/dev/null || true

echo -e "${GREEN}✅ Binaries extracted and organized${NC}"
echo ""

# Step 7: Clean up archives
echo -e "${YELLOW}🧹 Step 7: Cleaning up archive files...${NC}"
rm -f downloads/*.gz downloads/*.tgz

echo -e "${GREEN}✅ Archive files removed${NC}"
echo ""

# Step 8: Make binaries executable
echo -e "${YELLOW}🔧 Step 8: Making binaries executable...${NC}"
find downloads/{client,cni-plugins,controller,worker} -type f -exec chmod +x {} \;

echo -e "${GREEN}✅ Binaries are now executable${NC}"
echo ""

# Step 9: Install kubectl
echo -e "${YELLOW}⚙️  Step 9: Installing kubectl...${NC}"
sudo cp downloads/client/kubectl /usr/local/bin/

echo -e "${GREEN}✅ kubectl installed${NC}"
echo ""

# Step 10: Verify kubectl installation
echo -e "${YELLOW}✅ Step 10: Verifying kubectl installation...${NC}"
kubectl version --client

echo ""
echo -e "${GREEN}🎉 Jumpbox Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "Your WSL Debian jumpbox is now ready with:"
echo -e "  ${GREEN}✅ Required system packages${NC}"
echo -e "  ${GREEN}✅ Kubernetes binaries downloaded and organized${NC}"
echo -e "  ${GREEN}✅ kubectl installed and ready to use${NC}"
echo ""
echo "Directory structure created:"
echo "  📁 kubernetes-the-hard-way/downloads/client/     - kubectl, etcdctl"
echo "  📁 kubernetes-the-hard-way/downloads/controller/ - etcd, kube-apiserver, kube-controller-manager, kube-scheduler"  
echo "  📁 kubernetes-the-hard-way/downloads/worker/     - kubelet, kube-proxy, crictl, containerd, runc"
echo "  📁 kubernetes-the-hard-way/downloads/cni-plugins/ - CNI plugins"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo -e "  1. ${YELLOW}Continue with the Kubernetes the Hard Way tutorial${NC}"
echo -e "  2. ${YELLOW}Generate certificates and configuration files${NC}"
echo -e "  3. ${YELLOW}Use 'make status' to get SSH commands for your nodes${NC}"
echo ""

# Return to original directory
cd ..