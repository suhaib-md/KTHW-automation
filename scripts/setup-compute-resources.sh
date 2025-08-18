#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🖥️  Kubernetes the Hard Way - Compute Resources Setup${NC}"
echo "===================================================="
echo ""

# Check if infrastructure is deployed
if [ ! -f terraform.tfstate ]; then
    echo -e "${RED}❌ No infrastructure found. Please run 'make deploy' first.${NC}"
    exit 1
fi

# Check if we're in the kubernetes-the-hard-way directory
if [ ! -d "kubernetes-the-hard-way" ]; then
    echo -e "${RED}❌ kubernetes-the-hard-way directory not found. Please run 'make jumpbox-setup' first.${NC}"
    exit 1
fi

cd kubernetes-the-hard-way

# Configuration
BOOTSTRAP_KEY="/home/suhaib/.ssh/kubernetes-hard-way.pem"
JUMPBOX_KEY="$HOME/.ssh/id_rsa"
MACHINES_FILE="machines.txt"

echo -e "${YELLOW}🧹 Step 0: Cleaning up from previous deployments${NC}"

# Clean up local SSH known_hosts
echo "Cleaning SSH known_hosts..."
if [ -f ~/.ssh/known_hosts ]; then
    ssh-keygen -f ~/.ssh/known_hosts -R "server" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-0" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-1" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "server.kubernetes.local" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-0.kubernetes.local" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-1.kubernetes.local" 2>/dev/null || true
fi

# Clean up local files
rm -f "$MACHINES_FILE" hosts 2>/dev/null || true

echo ""

echo -e "${YELLOW}📋 Step 1: Creating machines.txt database${NC}"

# Get infrastructure details from Terraform
CONTROLLER_PUBLIC_IP=$(terraform -chdir=.. output -raw controller_public_ip)
CONTROLLER_PRIVATE_IP=$(terraform -chdir=.. output -raw controller_private_ip)
WORKER_0_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-0".public_ip')
WORKER_0_PRIVATE_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-0".private_ip')
WORKER_1_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-1".public_ip')
WORKER_1_PRIVATE_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-1".private_ip')

echo "Infrastructure discovered:"
echo "  Controller: Private=$CONTROLLER_PRIVATE_IP, Public=$CONTROLLER_PUBLIC_IP"
echo "  Worker 0:   Private=$WORKER_0_PRIVATE_IP, Public=$WORKER_0_PUBLIC_IP"
echo "  Worker 1:   Private=$WORKER_1_PRIVATE_IP, Public=$WORKER_1_PUBLIC_IP"
echo ""

# Create machines.txt
cat > "$MACHINES_FILE" << EOF
${CONTROLLER_PRIVATE_IP} server.kubernetes.local server
${WORKER_0_PRIVATE_IP} node-0.kubernetes.local node-0 10.200.0.0/24
${WORKER_1_PRIVATE_IP} node-1.kubernetes.local node-1 10.200.1.0/24
EOF

echo -e "${GREEN}✅ Created $MACHINES_FILE:${NC}"
cat "$MACHINES_FILE"
echo ""

# Read machines into arrays (keeping original logic)
declare -a MACHINE_IPS=()
declare -a MACHINE_FQDNS=()
declare -a MACHINE_HOSTS=()
declare -a MACHINE_SUBNETS=()
declare -a MACHINE_PUBLIC_IPS=()

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    fields=($line)
    MACHINE_IPS+=("${fields[0]}")
    MACHINE_FQDNS+=("${fields[1]}")
    MACHINE_HOSTS+=("${fields[2]}")
    MACHINE_SUBNETS+=("${fields[3]:-}")
    case "${fields[0]}" in
        "$CONTROLLER_PRIVATE_IP") PUBLIC_IP="$CONTROLLER_PUBLIC_IP" ;;
        "$WORKER_0_PRIVATE_IP") PUBLIC_IP="$WORKER_0_PUBLIC_IP" ;;
        "$WORKER_1_PRIVATE_IP") PUBLIC_IP="$WORKER_1_PUBLIC_IP" ;;
        *) PUBLIC_IP="" ;;
    esac
    MACHINE_PUBLIC_IPS+=("$PUBLIC_IP")
done < "$MACHINES_FILE"

echo -e "${YELLOW}🔑 Step 2: Setting up SSH access${NC}"

# Verify bootstrap key
if [ ! -f "$BOOTSTRAP_KEY" ]; then
    echo -e "${RED}❌ SSH key not found at $BOOTSTRAP_KEY${NC}"
    exit 1
fi
chmod 600 "$BOOTSTRAP_KEY"
echo "Using bootstrap SSH key: $BOOTSTRAP_KEY"

# Generate jumpbox key if missing
if [ ! -f "$JUMPBOX_KEY" ]; then
    echo "Generating new SSH key for jumpbox..."
    ssh-keygen -t rsa -b 4096 -f "$JUMPBOX_KEY" -N ""
    echo -e "${GREEN}✅ SSH key generated at $JUMPBOX_KEY${NC}"
fi
chmod 600 "$JUMPBOX_KEY"
echo ""

# Process each machine for SSH setup and hostname configuration
echo -e "${YELLOW}📝 Step 2a: Configuring SSH and hostnames${NC}"
for i in "${!MACHINE_HOSTS[@]}"; do
    IP="${MACHINE_IPS[i]}"
    PUBLIC_IP="${MACHINE_PUBLIC_IPS[i]}"
    FQDN="${MACHINE_FQDNS[i]}"
    HOST="${MACHINE_HOSTS[i]}"

    echo "Processing machine: $HOST (Private: $IP, Public: $PUBLIC_IP)..."

    # Copy key to admin user
    echo "  → Adding jumpbox key to admin@$PUBLIC_IP..."
    ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys" < "$JUMPBOX_KEY.pub"
    echo -e "    ${GREEN}✅ Jumpbox key added to admin@$HOST${NC}"

    # Setup root SSH access
    echo "  → Setting up root SSH access on $HOST..."
    ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
        "sudo mkdir -p /root/.ssh && \
         sudo chmod 700 /root/.ssh && \
         sudo touch /root/.ssh/authorized_keys && \
         sudo chmod 600 /root/.ssh/authorized_keys && \
         sudo chown root:root /root/.ssh/authorized_keys && \
         sudo bash -c 'cat >> /root/.ssh/authorized_keys'" < "$JUMPBOX_KEY.pub"
    echo -e "    ${GREEN}✅ Jumpbox key added to root@$HOST${NC}"

    # Enable PermitRootLogin and restart SSH
    echo "  → Configuring SSH daemon on $HOST..."
    ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
        "sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
         sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
         sudo systemctl restart ssh"
    echo -e "    ${GREEN}✅ SSH configured on $HOST${NC}"

    # Set hostname
    echo "  → Setting hostname on $HOST..."
    ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
        "sudo hostnamectl set-hostname $HOST && \
         sudo bash -c 'echo $HOST > /etc/hostname' && \
         sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts && \
         sudo bash -c 'echo \"127.0.1.1 $FQDN $HOST\" >> /etc/hosts' && \
         sudo systemctl restart systemd-hostnamed"
    echo -e "    ${GREEN}✅ Hostname set on $HOST${NC}"

    echo -e "${GREEN}✅ Completed processing $HOST${NC}"
    echo ""
done

echo -e "${YELLOW}📝 Step 3: Creating host lookup tables${NC}"

# Create hosts file
echo "" > hosts
echo "# Kubernetes The Hard Way" >> hosts
while read IP FQDN HOST SUBNET; do
    ENTRY="${IP} ${FQDN} ${HOST}"
    echo $ENTRY >> hosts
done < machines.txt

echo -e "${GREEN}✅ Created hosts file:${NC}"
cat hosts
echo ""

echo -e "${YELLOW}📝 Step 4: Updating /etc/hosts on jumpbox${NC}"

# Update local /etc/hosts with public IPs
echo "Updating local /etc/hosts file..."
sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
sudo sed -i '/# Added by Kubernetes the Hard Way setup/,$d' /etc/hosts
sudo sed -i '/# Kubernetes The Hard Way/,$d' /etc/hosts

echo "# Added by Kubernetes the Hard Way setup - External Access" | sudo tee -a /etc/hosts >/dev/null
echo "${CONTROLLER_PUBLIC_IP} server.kubernetes.local server" | sudo tee -a /etc/hosts >/dev/null
echo "${WORKER_0_PUBLIC_IP} node-0.kubernetes.local node-0" | sudo tee -a /etc/hosts >/dev/null
echo "${WORKER_1_PUBLIC_IP} node-1.kubernetes.local node-1" | sudo tee -a /etc/hosts >/dev/null

echo -e "${GREEN}✅ Updated local /etc/hosts with public IPs${NC}"
echo ""

echo -e "${YELLOW}📝 Step 5: Updating /etc/hosts on remote machines${NC}"

for i in "${!MACHINE_HOSTS[@]}"; do
    PUBLIC_IP="${MACHINE_PUBLIC_IPS[i]}"
    HOST="${MACHINE_HOSTS[i]}"
    echo "  Updating /etc/hosts on $HOST..."
    
    scp -o StrictHostKeyChecking=no hosts root@${HOST}:~/
    ssh -o StrictHostKeyChecking=no root@${HOST} "cat hosts >> /etc/hosts"
    echo -e "    ${GREEN}✅ Updated /etc/hosts on $HOST${NC}"
done

echo ""

echo -e "${YELLOW}🧪 Step 6: Final connectivity test${NC}"

echo "Testing hostname-based connectivity..."
for host in server node-0 node-1; do
    echo -n "  Testing $host: "
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$host" hostname >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi
done

echo ""
echo -e "${GREEN}🎉 COMPUTE RESOURCES SETUP COMPLETE!${NC}"
echo "================================================="
echo ""
echo "You can now connect to your machines:"
echo "  ssh root@server   (controller)"
echo "  ssh root@node-0   (worker 0)"  
echo "  ssh root@node-1   (worker 1)"
echo ""

cd ..