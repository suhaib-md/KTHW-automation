#!/bin/bash

set -e

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

echo -e "${YELLOW}📋 Step 1: Creating machines.txt database${NC}"

# Get infrastructure details from Terraform output
echo "Getting infrastructure details from Terraform..."

# Get SSH key path first
KEY_PATH=$(terraform -chdir=.. output -json ssh_key_info | jq -r '.private_key_path')

CONTROLLER_PUBLIC_IP=$(terraform -chdir=.. output -raw controller_public_ip)
CONTROLLER_PRIVATE_IP=$(terraform -chdir=.. output -raw controller_private_ip)
WORKER_0_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-0".public_ip')
WORKER_0_PRIVATE_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-0".private_ip')
WORKER_1_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-1".public_ip')
WORKER_1_PRIVATE_IP=$(terraform -chdir=.. output -json worker_nodes | jq -r '."node-1".private_ip')

echo "Waiting for instances to be fully ready..."
echo "  Controller: $CONTROLLER_PUBLIC_IP"
echo "  Worker 0:   $WORKER_0_PUBLIC_IP" 
echo "  Worker 1:   $WORKER_1_PUBLIC_IP"

# Create machines.txt file
cat > machines.txt << EOF
${CONTROLLER_PRIVATE_IP} server.kubernetes.local server
${WORKER_0_PRIVATE_IP} node-0.kubernetes.local node-0 10.200.0.0/24
${WORKER_1_PRIVATE_IP} node-1.kubernetes.local node-1 10.200.1.0/24
EOF

echo -e "${GREEN}✅ Created machines.txt:${NC}"
cat machines.txt
echo ""

echo -e "${YELLOW}🔑 Step 2: Setting up SSH access${NC}"

# Verify SSH key exists and fix permissions
if [ ! -f "$KEY_PATH" ]; then
    echo -e "  ${RED}❌ SSH key not found at $KEY_PATH${NC}"
    exit 1
fi

chmod 600 "$KEY_PATH"
echo "Using SSH key: $KEY_PATH"
echo ""

echo -e "${YELLOW}📝 Step 2a: Configuring SSH for remote access${NC}"

# Function to run SSH commands with retry
ssh_exec_retry() {
    local host=$1
    local command=$2
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i "$KEY_PATH" admin@$host "$command" 2>/dev/null; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo "    Attempt $attempt failed, retrying in 5 seconds..."
            sleep 5
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Function to copy files via SCP with retry
scp_copy_retry() {
    local src=$1
    local host=$2
    local dest=$3
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY_PATH" "$src" admin@$host:"$dest" 2>/dev/null; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo "    SCP attempt $attempt failed, retrying in 5 seconds..."
            sleep 5
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Enable root SSH access on each machine
echo "Configuring SSH access on each machine..."

for ip in $CONTROLLER_PUBLIC_IP $WORKER_0_PUBLIC_IP $WORKER_1_PUBLIC_IP; do
    echo "  Configuring SSH on $ip..."
    
    # Enable root login and set up SSH keys
    if ssh_exec_retry $ip "
        sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config &&
        sudo systemctl restart sshd &&
        sudo mkdir -p /root/.ssh &&
        sudo cp ~/.ssh/authorized_keys /root/.ssh/ &&
        sudo chown root:root /root/.ssh/authorized_keys &&
        sudo chmod 600 /root/.ssh/authorized_keys
    "; then
        echo -e "    ${GREEN}✅ SSH configured on $ip${NC}"
    else
        echo -e "    ${RED}❌ Failed to configure SSH on $ip after multiple attempts${NC}"
        exit 1
    fi
done

echo ""

echo -e "${YELLOW}🔑 Step 2b: Generating and distributing SSH keys for root access${NC}"

# Generate SSH key for the jumpbox if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generating SSH key for jumpbox..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    echo -e "${GREEN}✅ SSH key generated${NC}"
else
    echo -e "${GREEN}✅ SSH key already exists${NC}"
fi

echo ""

# Copy SSH public key to each machine for root access
echo "Distributing SSH key to all machines..."
while read IP FQDN HOST SUBNET; do
    echo "  Adding SSH key to $HOST ($IP)..."
    
    # First, get the public IP for this private IP
    if [ "$IP" = "$CONTROLLER_PRIVATE_IP" ]; then
        PUBLIC_IP=$CONTROLLER_PUBLIC_IP
    elif [ "$IP" = "$WORKER_0_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_0_PUBLIC_IP
    elif [ "$IP" = "$WORKER_1_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_1_PUBLIC_IP
    fi
    
    # Copy the jumpbox SSH key to root user - FIXED: Using KEY_PATH for authentication
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY_PATH" root@$PUBLIC_IP "
        mkdir -p /root/.ssh &&
        echo '$(cat ~/.ssh/id_rsa.pub)' >> /root/.ssh/authorized_keys &&
        chown -R root:root /root/.ssh &&
        chmod 700 /root/.ssh &&
        chmod 600 /root/.ssh/authorized_keys &&
        sort /root/.ssh/authorized_keys | uniq > /tmp/auth_keys_tmp &&
        mv /tmp/auth_keys_tmp /root/.ssh/authorized_keys
    " 2>/dev/null; then
        echo -e "    ${GREEN}✅ SSH key added to $HOST${NC}"
    else
        echo -e "    ${RED}❌ Failed to add SSH key to $HOST, retrying...${NC}"
        # Retry with more explicit error handling
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY_PATH" root@$PUBLIC_IP "
            mkdir -p /root/.ssh
            echo '$(cat ~/.ssh/id_rsa.pub)' >> /root/.ssh/authorized_keys
            chown -R root:root /root/.ssh
            chmod 700 /root/.ssh
            chmod 600 /root/.ssh/authorized_keys
            sort /root/.ssh/authorized_keys | uniq > /tmp/auth_keys_tmp
            mv /tmp/auth_keys_tmp /root/.ssh/authorized_keys
        " && echo -e "    ${GREEN}✅ SSH key added to $HOST (retry successful)${NC}" || {
            echo -e "    ${RED}❌ Failed to add SSH key to $HOST after retry${NC}"
            exit 1
        }
    fi
done < machines.txt

echo ""

echo -e "${YELLOW}🧪 Step 2c: Verifying root SSH access${NC}"
echo "Testing SSH access to each machine..."

while read IP FQDN HOST SUBNET; do
    # Get public IP for connection
    if [ "$IP" = "$CONTROLLER_PRIVATE_IP" ]; then
        PUBLIC_IP=$CONTROLLER_PUBLIC_IP
    elif [ "$IP" = "$WORKER_0_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_0_PUBLIC_IP
    elif [ "$IP" = "$WORKER_1_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_1_PUBLIC_IP
    fi
    
    echo "  Testing SSH to $HOST..."
    
    # Test both PEM key (should work) and id_rsa (what we just added)
    HOSTNAME_RESULT_PEM=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "$KEY_PATH" root@$PUBLIC_IP hostname 2>/dev/null)
    HOSTNAME_RESULT_RSA=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$PUBLIC_IP hostname 2>/dev/null)
    
    if [ "$HOSTNAME_RESULT_PEM" ] && [ "$HOSTNAME_RESULT_RSA" ]; then
        echo -e "    ${GREEN}✅ SSH to $HOST successful with both keys (hostname: $HOSTNAME_RESULT_RSA)${NC}"
    elif [ "$HOSTNAME_RESULT_PEM" ]; then
        echo -e "    ${YELLOW}⚠️  SSH to $HOST works with PEM key but not RSA key${NC}"
        echo -e "    ${YELLOW}⚠️  This may cause issues later - continuing anyway${NC}"
    else
        echo -e "    ${RED}❌ SSH to $HOST failed with both keys${NC}"
        exit 1
    fi
done < machines.txt

echo ""

echo -e "${YELLOW}🏷️  Step 3: Setting hostnames${NC}"

while read IP FQDN HOST SUBNET; do
    # Get public IP for connection
    if [ "$IP" = "$CONTROLLER_PRIVATE_IP" ]; then
        PUBLIC_IP=$CONTROLLER_PUBLIC_IP
    elif [ "$IP" = "$WORKER_0_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_0_PUBLIC_IP
    elif [ "$IP" = "$WORKER_1_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_1_PUBLIC_IP
    fi
    
    echo "  Setting hostname for $HOST..."
    
    # Set hostname and update /etc/hosts - Using KEY_PATH for reliable connection
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY_PATH" root@$PUBLIC_IP "
        sed -i 's/^127.0.1.1.*/127.0.1.1\t${FQDN} ${HOST}/' /etc/hosts &&
        hostnamectl set-hostname ${HOST} &&
        systemctl restart systemd-hostnamed
    "
    
    if [ $? -eq 0 ]; then
        echo -e "    ${GREEN}✅ Hostname set for $HOST${NC}"
    else
        echo -e "    ${RED}❌ Failed to set hostname for $HOST${NC}"
        exit 1
    fi
done < machines.txt

echo ""

echo -e "${YELLOW}🧪 Step 3a: Verifying hostnames${NC}"

while read IP FQDN HOST SUBNET; do
    # Get public IP for connection
    if [ "$IP" = "$CONTROLLER_PRIVATE_IP" ]; then
        PUBLIC_IP=$CONTROLLER_PUBLIC_IP
    elif [ "$IP" = "$WORKER_0_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_0_PUBLIC_IP
    elif [ "$IP" = "$WORKER_1_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_1_PUBLIC_IP
    fi
    
    echo "  Checking hostname for $HOST..."
    FQDN_RESULT=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY_PATH" root@$PUBLIC_IP "hostname --fqdn" 2>/dev/null)
    
    if [ "$FQDN_RESULT" = "$FQDN" ]; then
        echo -e "    ${GREEN}✅ Hostname verified: $FQDN_RESULT${NC}"
    else
        echo -e "    ${YELLOW}⚠️  Hostname mismatch: expected $FQDN, got $FQDN_RESULT${NC}"
    fi
done < machines.txt

echo ""

echo -e "${YELLOW}📝 Step 4: Creating host lookup table${NC}"

# Create hosts file
echo "" > hosts
echo "# Kubernetes The Hard Way" >> hosts

# Add entries to hosts file
while read IP FQDN HOST SUBNET; do
    ENTRY="${IP} ${FQDN} ${HOST}"
    echo "$ENTRY" >> hosts
done < machines.txt

echo -e "${GREEN}✅ Created hosts file:${NC}"
cat hosts
echo ""

echo -e "${YELLOW}📝 Step 5: Adding /etc/hosts entries to jumpbox${NC}"

# Backup existing /etc/hosts
sudo cp /etc/hosts /etc/hosts.backup

# Add entries to local /etc/hosts
sudo sh -c 'cat hosts >> /etc/hosts'

echo -e "${GREEN}✅ Updated local /etc/hosts file${NC}"
echo ""

echo -e "${YELLOW}📝 Step 6: Adding /etc/hosts entries to remote machines${NC}"

while read IP FQDN HOST SUBNET; do
    # Get public IP for connection
    if [ "$IP" = "$CONTROLLER_PRIVATE_IP" ]; then
        PUBLIC_IP=$CONTROLLER_PUBLIC_IP
    elif [ "$IP" = "$WORKER_0_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_0_PUBLIC_IP
    elif [ "$IP" = "$WORKER_1_PRIVATE_IP" ]; then
        PUBLIC_IP=$WORKER_1_PUBLIC_IP
    fi
    
    echo "  Updating /etc/hosts on $HOST..."
    
    # Copy hosts file and append to /etc/hosts - Using KEY_PATH for reliable connection
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY_PATH" hosts root@$PUBLIC_IP:~/
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY_PATH" root@$PUBLIC_IP "cat hosts >> /etc/hosts"
    
    if [ $? -eq 0 ]; then
        echo -e "    ${GREEN}✅ Updated /etc/hosts on $HOST${NC}"
    else
        echo -e "    ${RED}❌ Failed to update /etc/hosts on $HOST${NC}"
        exit 1
    fi
done < machines.txt

echo ""

echo -e "${YELLOW}🧪 Step 7: Final connectivity test${NC}"
echo "Testing hostname-based connectivity..."

# Test connectivity using hostnames (fallback to KEY_PATH if id_rsa doesn't work yet)
for host in server node-0 node-1; do
    echo "  Testing connection to $host..."
    
    # Try with id_rsa first (the goal), fallback to KEY_PATH
    RESULT=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$host hostname 2>/dev/null || \
             ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "$KEY_PATH" root@$host hostname 2>/dev/null)
    
    if [ "$RESULT" = "$host" ]; then
        echo -e "    ${GREEN}✅ Successfully connected to $host${NC}"
    else
        echo -e "    ${RED}❌ Failed to connect to $host${NC}"
        echo "    Expected: $host, Got: $RESULT"
        exit 1
    fi
done

echo ""
echo -e "${GREEN}🎉 COMPUTE RESOURCES SETUP COMPLETE!${NC}"
echo "================================================="
echo ""
echo "Summary of what was configured:"
echo -e "  ${GREEN}✅ Machine database created (machines.txt)${NC}"
echo -e "  ${GREEN}✅ SSH access configured for all machines${NC}"
echo -e "  ${GREEN}✅ Root SSH keys distributed${NC}"
echo -e "  ${GREEN}✅ Hostnames set on all machines${NC}"
echo -e "  ${GREEN}✅ Host lookup table created and distributed${NC}"
echo -e "  ${GREEN}✅ Hostname-based connectivity verified${NC}"
echo ""
echo "You can now connect to machines using:"
echo -e "  ${YELLOW}ssh root@server${NC}   (controller node)"
echo -e "  ${YELLOW}ssh root@node-0${NC}   (worker node 0)"
echo -e "  ${YELLOW}ssh root@node-1${NC}   (worker node 1)"
echo ""
echo "Files created:"
echo "  📁 kubernetes-the-hard-way/machines.txt"
echo "  📁 kubernetes-the-hard-way/hosts"
echo ""
echo -e "${BLUE}Next step: Generate certificates and configuration files${NC}"
echo ""

# Return to original directory
cd ..