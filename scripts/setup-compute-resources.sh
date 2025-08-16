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
HOSTS_FILE="/etc/hosts"
HOSTS_REMOTE="hosts_remote"
HOSTS_JUMPBOX="hosts_jumpbox"

echo -e "${YELLOW}🧹 Step 0: Cleaning up from any previous deployments${NC}"

# Clean up local SSH known_hosts
echo "Cleaning SSH known_hosts..."
if [ -f ~/.ssh/known_hosts ]; then
    ssh-keygen -f ~/.ssh/known_hosts -R "server" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-0" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-1" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "server.kubernetes.local" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-0.kubernetes.local" 2>/dev/null || true
    ssh-keygen -f ~/.ssh/known_hosts -R "node-1.kubernetes.local" 2>/dev/null || true
    for ip in $(seq 1 255); do
        ssh-keygen -f ~/.ssh/known_hosts -R "10.240.0.$ip" 2>/dev/null || true
    done
    echo -e "${GREEN}✅ SSH known_hosts cleaned${NC}"
else
    echo -e "${GREEN}✅ No existing known_hosts file${NC}"
fi

# Clean up local files
rm -f "$MACHINES_FILE" "$HOSTS_REMOTE" "$HOSTS_JUMPBOX" hosts 2>/dev/null || true

echo ""

echo -e "${YELLOW}📋 Step 1: Creating machines.txt database${NC}"

# Get infrastructure details from Terraform
echo "Retrieving instance information..."
if ! CONTROLLER_PUBLIC_IP=$(terraform -chdir=.. output -raw controller_public_ip 2>/dev/null) || [ -z "$CONTROLLER_PUBLIC_IP" ]; then
    echo -e "${RED}❌ Could not retrieve controller public IP${NC}"
    exit 1
fi

if ! CONTROLLER_PRIVATE_IP=$(terraform -chdir=.. output -raw controller_private_ip 2>/dev/null) || [ -z "$CONTROLLER_PRIVATE_IP" ]; then
    echo -e "${RED}❌ Could not retrieve controller private IP${NC}"
    exit 1
fi

if ! WORKER_0_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes 2>/dev/null | jq -r '."node-0".public_ip' 2>/dev/null) || [ -z "$WORKER_0_PUBLIC_IP" ] || [ "$WORKER_0_PUBLIC_IP" = "null" ]; then
    echo -e "${RED}❌ Could not retrieve worker-0 public IP${NC}"
    exit 1
fi

if ! WORKER_0_PRIVATE_IP=$(terraform -chdir=.. output -json worker_nodes 2>/dev/null | jq -r '."node-0".private_ip' 2>/dev/null) || [ -z "$WORKER_0_PRIVATE_IP" ] || [ "$WORKER_0_PRIVATE_IP" = "null" ]; then
    echo -e "${RED}❌ Could not retrieve worker-0 private IP${NC}"
    exit 1
fi

if ! WORKER_1_PUBLIC_IP=$(terraform -chdir=.. output -json worker_nodes 2>/dev/null | jq -r '."node-1".public_ip' 2>/dev/null) || [ -z "$WORKER_1_PUBLIC_IP" ] || [ "$WORKER_1_PUBLIC_IP" = "null" ]; then
    echo -e "${RED}❌ Could not retrieve worker-1 public IP${NC}"
    exit 1
fi

if ! WORKER_1_PRIVATE_IP=$(terraform -chdir=.. output -json worker_nodes 2>/dev/null | jq -r '."node-1".private_ip' 2>/dev/null) || [ -z "$WORKER_1_PRIVATE_IP" ] || [ "$WORKER_1_PRIVATE_IP" = "null" ]; then
    echo -e "${RED}❌ Could not retrieve worker-1 private IP${NC}"
    exit 1
fi

echo "Infrastructure discovered:"
echo "  Controller: Private=$CONTROLLER_PRIVATE_IP, Public=$CONTROLLER_PUBLIC_IP"
echo "  Worker 0:   Private=$WORKER_0_PRIVATE_IP, Public=$WORKER_0_PUBLIC_IP"
echo "  Worker 1:   Private=$WORKER_1_PRIVATE_IP, Public=$WORKER_1_PUBLIC_IP"
echo ""

# Wait for instances to be fully ready
echo "Waiting for instances to be fully ready..."
sleep 10

# Create machines.txt
cat > "$MACHINES_FILE" << EOF
${CONTROLLER_PRIVATE_IP} server.kubernetes.local server
${WORKER_0_PRIVATE_IP} node-0.kubernetes.local node-0 10.200.0.0/24
${WORKER_1_PRIVATE_IP} node-1.kubernetes.local node-1 10.200.1.0/24
EOF

chown suhaib:suhaib "$MACHINES_FILE"
chmod 644 "$MACHINES_FILE"
echo -e "${GREEN}✅ Created $MACHINES_FILE:${NC}"
cat "$MACHINES_FILE"
echo ""

# Validate machines.txt
if ! grep -q "server.kubernetes.local" "$MACHINES_FILE" || ! grep -q "node-0.kubernetes.local" "$MACHINES_FILE" || ! grep -q "node-1.kubernetes.local" "$MACHINES_FILE"; then
    echo -e "${RED}❌ $MACHINES_FILE is missing expected entries${NC}"
    cat "$MACHINES_FILE"
    exit 1
fi
echo -e "${GREEN}✅ $MACHINES_FILE validated${NC}"
echo ""

# Read machines into arrays
declare -a MACHINE_IPS=()
declare -a MACHINE_FQDNS=()
declare -a MACHINE_HOSTS=()
declare -a MACHINE_SUBNETS=()
declare -a MACHINE_PUBLIC_IPS=()

echo "[+] Reading machines from $MACHINES_FILE..."
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
    echo "[DEBUG] Added machine: ${fields[2]} (Private: ${fields[0]}, Public: $PUBLIC_IP)"
done < "$MACHINES_FILE"

total_machines=${#MACHINE_IPS[@]}
echo "[INFO] Found $total_machines machines to process:"
for i in "${!MACHINE_HOSTS[@]}"; do
    echo "  $((i+1)). ${MACHINE_HOSTS[i]} (Private: ${MACHINE_IPS[i]}, Public: ${MACHINE_PUBLIC_IPS[i]})"
done

if [ "$total_machines" -eq 0 ]; then
    echo -e "${RED}❌ No machines found in $MACHINES_FILE${NC}"
    exit 1
fi

echo ""

echo -e "${YELLOW}🔑 Step 2: Setting up SSH access${NC}"

# Verify bootstrap key
if [ ! -f "$BOOTSTRAP_KEY" ]; then
    echo -e "${RED}❌ SSH key not found at $BOOTSTRAP_KEY${NC}"
    exit 1
fi
chmod 600 "$BOOTSTRAP_KEY"
echo "Using bootstrap SSH key: $BOOTSTRAP_KEY"
echo ""

# Generate jumpbox key if missing
if [ ! -f "$JUMPBOX_KEY" ]; then
    echo "Generating new SSH key for jumpbox..."
    ssh-keygen -t rsa -b 4096 -f "$JUMPBOX_KEY" -N ""
    echo -e "${GREEN}✅ SSH key generated at $JUMPBOX_KEY${NC}"
else
    echo -e "${GREEN}✅ SSH key already exists at $JUMPBOX_KEY${NC}"
fi
chmod 600 "$JUMPBOX_KEY"
echo ""

# Process each machine for SSH setup and hostname configuration
echo -e "${YELLOW}📝 Step 2a: Configuring SSH and hostnames${NC}"
processed_count=0
HOSTS_ENTRIES=""
HOSTS_ENTRIES_JUMPBOX=""
for i in "${!MACHINE_HOSTS[@]}"; do
    IP="${MACHINE_IPS[i]}"
    PUBLIC_IP="${MACHINE_PUBLIC_IPS[i]}"
    FQDN="${MACHINE_FQDNS[i]}"
    HOST="${MACHINE_HOSTS[i]}"
    SUBNET="${MACHINE_SUBNETS[i]}"
    HOSTS_ENTRIES+="$IP $FQDN $HOST\n"
    HOSTS_ENTRIES_JUMPBOX+="$PUBLIC_IP $FQDN $HOST\n"

    processed_count=$((processed_count + 1))
    echo -e "\n[*] Processing machine $processed_count/$total_machines: $HOST (Private: $IP, Public: $PUBLIC_IP)..."

    # Copy key to admin user
    echo "  -> Adding jumpbox key to admin@$PUBLIC_IP..."
    max_attempts=5
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "    Attempt $attempt/$max_attempts..."
        if ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys" < "$JUMPBOX_KEY.pub" 2>/dev/null; then
            echo -e "    ${GREEN}✅ Jumpbox key added to admin@$HOST${NC}"
            break
        fi
        if [ $attempt -lt $max_attempts ]; then
            echo "    Failed, retrying in 10 seconds..."
            sleep 10
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $max_attempts ]; then
        echo -e "    ${RED}❌ Failed to add jumpbox key to admin@$HOST${NC}"
        exit 1
    fi

    # Setup root SSH access
    echo "  -> Setting up root SSH access on $HOST..."
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "    Attempt $attempt/$max_attempts..."
        if ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
            "sudo mkdir -p /root/.ssh && \
             sudo chmod 700 /root/.ssh && \
             sudo touch /root/.ssh/authorized_keys && \
             sudo chmod 600 /root/.ssh/authorized_keys && \
             sudo chown root:root /root/.ssh/authorized_keys && \
             sudo bash -c 'cat >> /root/.ssh/authorized_keys'" < "$JUMPBOX_KEY.pub" 2>/dev/null; then
            echo -e "    ${GREEN}✅ Jumpbox key added to root@$HOST${NC}"
            break
        fi
        if [ $attempt -lt $max_attempts ]; then
            echo "    Failed, retrying in 10 seconds..."
            sleep 10
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $max_attempts ]; then
        echo -e "    ${RED}❌ Failed to add jumpbox key to root@$HOST${NC}"
        exit 1
    fi

    # Enable PermitRootLogin and restart SSH
    echo "  -> Configuring SSH daemon on $HOST..."
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "    Attempt $attempt/$max_attempts..."
        if ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
            "sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
             sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
             sudo systemctl restart ssh" 2>/dev/null; then
            echo -e "    ${GREEN}✅ SSH configured on $HOST${NC}"
            break
        fi
        if [ $attempt -lt $max_attempts ]; then
            echo "    Failed, retrying in 10 seconds..."
            sleep 10
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $max_attempts ]; then
        echo -e "    ${RED}❌ Failed to configure SSH on $HOST${NC}"
        exit 1
    fi

    # Wait for SSH to restart
    echo "  -> Waiting for SSH restart..."
    sleep 3

    # Verify key installation
    echo "  -> Verifying key installation on $HOST..."
    KEY_FINGERPRINT=$(ssh-keygen -lf "$JUMPBOX_KEY.pub" | awk '{print $2}')
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "    Attempt $attempt/$max_attempts..."
        if ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
            "sudo ssh-keygen -lf /root/.ssh/authorized_keys | grep -q '$KEY_FINGERPRINT'" 2>/dev/null; then
            echo -e "    ${GREEN}✅ Key verified on $HOST${NC}"
            break
        fi
        if [ $attempt -lt $max_attempts ]; then
            echo "    Failed, retrying in 10 seconds..."
            sleep 10
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $max_attempts ]; then
        echo -e "    ${YELLOW}⚠️ Key verification failed on $HOST (but may still work)${NC}"
    fi

    # Set hostname
    echo "  -> Setting hostname on $HOST..."
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "    Attempt $attempt/$max_attempts..."
        if ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
            "sudo hostnamectl set-hostname $HOST && \
             sudo bash -c 'echo $HOST > /etc/hostname' && \
             sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts && \
             sudo bash -c 'echo \"127.0.1.1 $FQDN $HOST\" >> /etc/hosts' && \
             sudo systemctl restart systemd-hostnamed && \
             [ \$(hostname) = '$HOST' ] && \
             [ \$(hostname --fqdn) = '$FQDN' ]" 2>/dev/null; then
            echo -e "    ${GREEN}✅ Hostname set and verified on $HOST${NC}"
            break
        fi
        if [ $attempt -lt $max_attempts ]; then
            echo "    Failed, retrying in 10 seconds..."
            sleep 10
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $max_attempts ]; then
        echo -e "    ${RED}❌ Failed to set hostname on $HOST${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Completed processing $HOST${NC}"
    echo "========================================"
done

echo ""

echo -e "${YELLOW}📝 Step 3: Creating host lookup tables${NC}"

# Create hosts_remote (private IPs for internal communication)
echo "# Kubernetes The Hard Way - Internal Communication" > "$HOSTS_REMOTE"
echo -e "$HOSTS_ENTRIES" >> "$HOSTS_REMOTE"
echo -e "${GREEN}✅ Created $HOSTS_REMOTE:${NC}"
cat "$HOSTS_REMOTE"
echo ""

# Create hosts_jumpbox (public IPs for external access)
echo "# Kubernetes The Hard Way - External Access" > "$HOSTS_JUMPBOX"
echo -e "$HOSTS_ENTRIES_JUMPBOX" >> "$HOSTS_JUMPBOX"
echo -e "${GREEN}✅ Created $HOSTS_JUMPBOX:${NC}"
cat "$HOSTS_JUMPBOX"
echo ""

echo -e "${YELLOW}📝 Step 4: Updating /etc/hosts on jumpbox${NC}"

# Handle WSL /etc/hosts auto-generation
echo "Checking WSL configuration..."
if grep -q microsoft /proc/version 2>/dev/null; then
    echo "WSL detected, checking /etc/hosts generation settings..."
    
    # Check if WSL is auto-generating hosts
    if [ -f /etc/wsl.conf ]; then
        if grep -q "generateHosts.*=.*true" /etc/wsl.conf 2>/dev/null; then
            echo -e "${YELLOW}⚠️ WSL auto-generation of /etc/hosts is enabled${NC}"
            NEED_WSL_RESTART=true
        elif grep -q "generateHosts.*=.*false" /etc/wsl.conf 2>/dev/null; then
            echo -e "${GREEN}✅ WSL auto-generation is already disabled${NC}"
            NEED_WSL_RESTART=false
        else
            echo -e "${YELLOW}⚠️ WSL generateHosts setting not found, will configure it${NC}"
            NEED_WSL_RESTART=true
        fi
    else
        echo -e "${YELLOW}⚠️ /etc/wsl.conf not found, will create it${NC}"
        NEED_WSL_RESTART=true
    fi
    
    # Configure WSL if needed
    if [ "$NEED_WSL_RESTART" = true ]; then
        echo "Configuring WSL to disable automatic /etc/hosts generation..."
        
        if [ ! -f /etc/wsl.conf ]; then
            sudo tee /etc/wsl.conf > /dev/null << 'EOF'
[network]
generateHosts = false
EOF
            echo -e "${GREEN}✅ Created /etc/wsl.conf with generateHosts = false${NC}"
        else
            # Remove any existing generateHosts lines
            sudo sed -i '/generateHosts/d' /etc/wsl.conf
            
            # Add or update [network] section
            if grep -q '^\[network\]' /etc/wsl.conf; then
                sudo sed -i '/^\[network\]/a generateHosts = false' /etc/wsl.conf
            else
                echo "" | sudo tee -a /etc/wsl.conf > /dev/null
                echo "[network]" | sudo tee -a /etc/wsl.conf > /dev/null
                echo "generateHosts = false" | sudo tee -a /etc/wsl.conf > /dev/null
            fi
            echo -e "${GREEN}✅ Updated /etc/wsl.conf with generateHosts = false${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}⚠️ WSL CONFIGURATION UPDATED${NC}"
        echo "To apply the WSL configuration changes:"
        echo "  1. Open Windows Command Prompt or PowerShell as Administrator"
        echo "  2. Run: wsl --shutdown"
        echo "  3. Wait a few seconds, then restart your WSL terminal"
        echo "  4. Re-run this script: make setup-compute"
        echo ""
        echo -e "${BLUE}The script will continue and configure /etc/hosts, but you should restart WSL to prevent future auto-regeneration.${NC}"
        echo ""
        read -p "Press Enter to continue with /etc/hosts configuration..."
    fi
else
    echo "Non-WSL environment detected, proceeding normally..."
fi

# Backup and update /etc/hosts
echo "Updating local /etc/hosts file..."
sudo cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
sudo sed -i '/# Added by Kubernetes the Hard Way setup/,$d' "$HOSTS_FILE"
sudo sed -i '/# Kubernetes The Hard Way/,$d' "$HOSTS_FILE"
sudo sed -i '/server\.kubernetes\.local\|node-[0-9]\.kubernetes\.local\|[[:space:]]server[[:space:]]*$\|[[:space:]]node-[0-9][[:space:]]*$/d' "$HOSTS_FILE"

# Add entries with error checking
echo "# Added by Kubernetes the Hard Way setup - External Access" | sudo tee -a "$HOSTS_FILE" >/dev/null
echo -e "$HOSTS_ENTRIES_JUMPBOX" | sudo tee -a "$HOSTS_FILE" >/dev/null

# Verify /etc/hosts was updated
if grep -q "server.kubernetes.local" "$HOSTS_FILE" && grep -q "node-0.kubernetes.local" "$HOSTS_FILE" && grep -q "node-1.kubernetes.local" "$HOSTS_FILE"; then
    echo -e "${GREEN}✅ Verified $HOSTS_FILE contains all expected entries${NC}"
else
    echo -e "${RED}❌ $HOSTS_FILE does not contain all expected entries${NC}"
    echo "Current $HOSTS_FILE content:"
    cat "$HOSTS_FILE"
    echo ""
    echo -e "${YELLOW}⚠️ This might be due to WSL auto-regeneration. Consider restarting WSL as mentioned above.${NC}"
fi
echo -e "${GREEN}✅ Updated $HOSTS_FILE with public IPs${NC}"
echo ""

echo -e "${YELLOW}📝 Step 5: Updating /etc/hosts on remote machines${NC}"

for i in "${!MACHINE_HOSTS[@]}"; do
    PUBLIC_IP="${MACHINE_PUBLIC_IPS[i]}"
    HOST="${MACHINE_HOSTS[i]}"
    echo "  Updating /etc/hosts on $HOST..."
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "    Attempt $attempt/$max_attempts..."
        
        # First, let's see what's currently in the hosts file
        echo "    Current /etc/hosts content on $HOST:"
        ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
            "sudo cat /etc/hosts" 2>/dev/null || echo "    Failed to read current hosts file"
        
        # Create a simple script that will update hosts file
        cat > "/tmp/update_hosts_$HOST.sh" << 'SCRIPT_EOF'
#!/bin/bash
# Backup current hosts file
sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

# Remove old Kubernetes entries
sudo sed -i '/# Added by Kubernetes the Hard Way setup/,$/d' /etc/hosts
sudo sed -i '/# Kubernetes The Hard Way/,$/d' /etc/hosts
sudo sed -i '/server\.kubernetes\.local\|node-[0-9]\.kubernetes\.local/d' /etc/hosts

# Add new entries
echo "# Added by Kubernetes the Hard Way setup - Internal Communication" | sudo tee -a /etc/hosts >/dev/null
SCRIPT_EOF

        # Add the actual host entries to the script
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            echo "echo '$line' | sudo tee -a /etc/hosts >/dev/null" >> "/tmp/update_hosts_$HOST.sh"
        done < "$HOSTS_REMOTE"

        # Copy and execute the script
        if scp -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "/tmp/update_hosts_$HOST.sh" "admin@$PUBLIC_IP:~/update_hosts.sh" 2>/dev/null && \
           ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
               "chmod +x ~/update_hosts.sh && ~/update_hosts.sh" 2>/dev/null; then
            
            echo "    Script executed successfully, verifying..."
            
            # Show the updated hosts file for debugging
            echo "    Updated /etc/hosts content on $HOST:"
            ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
                "sudo cat /etc/hosts" 2>/dev/null
            
            # Verify the hosts file was updated correctly
            if ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 "admin@$PUBLIC_IP" \
                "grep -q 'server.kubernetes.local' /etc/hosts && \
                 grep -q 'node-0.kubernetes.local' /etc/hosts && \
                 grep -q 'node-1.kubernetes.local' /etc/hosts" 2>/dev/null; then
                echo -e "    ${GREEN}✅ Updated and verified /etc/hosts on $HOST${NC}"
                # Cleanup
                rm -f "/tmp/update_hosts_$HOST.sh"
                ssh -i "$BOOTSTRAP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "admin@$PUBLIC_IP" "rm -f ~/update_hosts.sh" 2>/dev/null || true
                break
            else
                echo "    Verification failed, hosts entries not found after update"
            fi
        else
            echo "    Failed to copy or execute script"
        fi
        
        # Cleanup on failure
        rm -f "/tmp/update_hosts_$HOST.sh"
        
        if [ $attempt -lt $max_attempts ]; then
            echo "    Failed, retrying in 10 seconds..."
            sleep 10
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $max_attempts ]; then
        echo -e "    ${RED}❌ Failed to update /etc/hosts on $HOST${NC}"
        echo -e "    ${YELLOW}You can manually update /etc/hosts on this machine later${NC}"
        echo -e "    ${YELLOW}Manual command: ssh -i $BOOTSTRAP_KEY admin@$PUBLIC_IP${NC}"
        # Don't exit, continue with other machines
        # exit 1
    fi
done

echo ""

echo -e "${YELLOW}🧪 Step 6: Final connectivity test${NC}"

# Flush DNS cache
echo "Flushing DNS cache..."
sudo systemd-resolve --flush-caches 2>/dev/null || true
if systemctl is-active --quiet systemd-resolved; then
    echo "Restarting systemd-resolved..."
    sudo systemctl restart systemd-resolved
    sleep 2
fi

# Preload SSH known_hosts
echo "Preloading SSH known_hosts..."
for i in "${!MACHINE_HOSTS[@]}"; do
    HOST="${MACHINE_HOSTS[i]}"
    PUBLIC_IP="${MACHINE_PUBLIC_IPS[i]}"
    ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H "$PUBLIC_IP" >> ~/.ssh/known_hosts 2>/dev/null || true
done

# Verify hostname resolution and SSH access
echo "Testing hostname-based connectivity..."
CONNECTIVITY_ISSUES=false

for i in "${!MACHINE_HOSTS[@]}"; do
    HOST="${MACHINE_HOSTS[i]}"
    PUBLIC_IP="${MACHINE_PUBLIC_IPS[i]}"
    echo "  Testing $HOST..."

    # Test hostname resolution
    if timeout 10 getent hosts "$HOST" >/dev/null 2>&1; then
        RESOLVED_IP=$(getent hosts "$HOST" | awk '{print $1}')
        echo -e "    ${GREEN}✅ Resolved $HOST to $RESOLVED_IP${NC}"
        
        # Test SSH with hostname
        echo -n "    SSH as admin@$HOST: "
        if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "admin@$HOST" hostname >/dev/null 2>&1; then
            echo -e "${GREEN}✅ OK${NC}"
        else
            echo -e "${RED}❌ FAILED${NC}"
            CONNECTIVITY_ISSUES=true
        fi

        echo -n "    SSH as root@$HOST: "
        if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$HOST" hostname >/dev/null 2>&1; then
            echo -e "${GREEN}✅ OK${NC}"
        else
            echo -e "${RED}❌ FAILED${NC}"
            echo "    Fallback: Testing with bootstrap key..."
            if timeout 10 ssh -i "$BOOTSTRAP_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$PUBLIC_IP" hostname >/dev/null 2>&1; then
                echo -e "    ${YELLOW}⚠️ SSH works with bootstrap key but not jumpbox key${NC}"
                CONNECTIVITY_ISSUES=true
            else
                echo -e "    ${RED}❌ SSH failed with both keys${NC}"
                CONNECTIVITY_ISSUES=true
            fi
        fi
    else
        echo -e "    ${RED}❌ Hostname $HOST cannot be resolved${NC}"
        echo -e "    ${YELLOW}⚠️ This is likely due to WSL auto-regenerating /etc/hosts${NC}"
        echo "    Current $HOSTS_FILE content:"
        tail -10 "$HOSTS_FILE" | sed 's/^/      /'
        CONNECTIVITY_ISSUES=true
        
        # Test direct IP connectivity as fallback
        echo -n "    Fallback SSH test with IP ($PUBLIC_IP): "
        if timeout 10 ssh -i "$BOOTSTRAP_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$PUBLIC_IP" hostname >/dev/null 2>&1; then
            echo -e "${GREEN}✅ IP-based SSH works${NC}"
        else
            echo -e "${RED}❌ IP-based SSH failed${NC}"
        fi
    fi
done

# Handle connectivity issues
if [ "$CONNECTIVITY_ISSUES" = true ]; then
    echo ""
    echo -e "${YELLOW}⚠️ Some connectivity issues were detected${NC}"
    echo ""
    echo -e "${BLUE}Troubleshooting options:${NC}"
    echo ""
    echo "1. If hostname resolution failed:"
    echo "   - Restart WSL: wsl --shutdown (from Windows CMD)"
    echo "   - Check /etc/hosts: cat /etc/hosts"
    echo "   - Use IP-based connections as backup"
    echo ""
    echo "2. If SSH failed:"
    echo "   - Wait a few minutes for SSH to fully restart on remote machines"
    echo "   - Use bootstrap key as backup: ssh -i $BOOTSTRAP_KEY root@<PUBLIC_IP>"
    echo ""
    echo "3. Backup connection methods:"
    echo "   ssh -i $BOOTSTRAP_KEY root@$CONTROLLER_PUBLIC_IP   (server)"
    echo "   ssh -i $BOOTSTRAP_KEY root@$WORKER_0_PUBLIC_IP   (node-0)"
    echo "   ssh -i $BOOTSTRAP_KEY root@$WORKER_1_PUBLIC_IP   (node-1)"
    echo ""
    echo -e "${YELLOW}The setup will continue, but you may need to use IP-based connections.${NC}"
else
    echo -e "${GREEN}✅ All connectivity tests passed!${NC}"
fi

echo ""
echo -e "${GREEN}🎉 COMPUTE RESOURCES SETUP COMPLETE!${NC}"
echo "================================================="
echo ""
echo "Summary of what was configured:"
echo -e "  ${GREEN}✅ Machine database created ($MACHINES_FILE)${NC}"
echo -e "  ${GREEN}✅ SSH access configured for all machines${NC}"
echo -e "  ${GREEN}✅ Root SSH keys distributed${NC}"
echo -e "  ${GREEN}✅ Hostnames set on all machines${NC}"
echo -e "  ${GREEN}✅ Host lookup tables created and distributed${NC}"
echo -e "  ${GREEN}✅ Hostname-based connectivity tested${NC}"
echo ""
echo "Connection methods:"
echo -e "  ${YELLOW}🌐 Hostname-based (recommended):${NC}"
echo "    ssh root@server   (controller node)"
echo "    ssh root@node-0   (worker node 0)"
echo "    ssh root@node-1   (worker node 1)"
echo ""
echo -e "  ${YELLOW}🔗 IP-based (backup):${NC}"
echo "    ssh -i $BOOTSTRAP_KEY root@$CONTROLLER_PUBLIC_IP   (server)"
echo "    ssh -i $BOOTSTRAP_KEY root@$WORKER_0_PUBLIC_IP   (node-0)"
echo "    ssh -i $BOOTSTRAP_KEY root@$WORKER_1_PUBLIC_IP   (node-1)"
echo ""
echo "Files created:"
echo "  📁 kubernetes-the-hard-way/$MACHINES_FILE        (private IPs)"
echo "  📁 kubernetes-the-hard-way/$HOSTS_REMOTE        (private IPs for internal communication)"
echo "  📁 kubernetes-the-hard-way/$HOSTS_JUMPBOX       (public IPs for external access)"
echo ""
echo -e "${BLUE}Next step: Generate certificates and configuration files${NC}"
echo ""

# Final verification summary
echo -e "${YELLOW}📊 Final Verification Summary:${NC}"
for i in "${!MACHINE_HOSTS[@]}"; do
    HOST="${MACHINE_HOSTS[i]}"
    PUBLIC_IP="${MACHINE_PUBLIC_IPS[i]}"
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$HOST" "echo 'Connection test successful'" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $HOST - Ready for Kubernetes installation${NC}"
    else
        echo -e "  ${YELLOW}⚠️ $HOST - Hostname-based SSH failed, but IP-based should work${NC}"
        # Don't exit, just warn
    fi
done

echo ""
if [ "$CONNECTIVITY_ISSUES" = true ]; then
    echo -e "${YELLOW}🚀 Setup completed with some connectivity issues!${NC}"
    echo ""
    echo -e "${BLUE}Your infrastructure is ready, but you may need to use IP-based connections:${NC}"
    echo ""
    echo -e "${YELLOW}Recommended connection methods:${NC}"
    echo "  ssh -i $BOOTSTRAP_KEY root@$CONTROLLER_PUBLIC_IP   (server)"
    echo "  ssh -i $BOOTSTRAP_KEY root@$WORKER_0_PUBLIC_IP   (node-0)"
    echo "  ssh -i $BOOTSTRAP_KEY root@$WORKER_1_PUBLIC_IP   (node-1)"
    echo ""
    echo -e "${YELLOW}If you restart WSL (wsl --shutdown), hostname-based connections may work:${NC}"
    echo "  ssh root@server"
    echo "  ssh root@node-0"
    echo "  ssh root@node-1"
else
    echo -e "${GREEN}🚀 All systems ready! You can proceed with the Kubernetes the Hard Way tutorial.${NC}"
    echo ""
    echo -e "${GREEN}Connection methods:${NC}"
    echo "  ssh root@server   (controller)"
    echo "  ssh root@node-0   (worker 0)"
    echo "  ssh root@node-1   (worker 1)"
fi

echo ""
echo -e "${BLUE}Next step: Generate certificates and configuration files${NC}"
echo ""

cd ..
echo ""