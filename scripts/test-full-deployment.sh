#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Helper functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    local warning_only="${4:-false}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "  Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        result=$?
    else
        result=$?
    fi
    
    if [ $result -eq $expected_result ]; then
        echo -e "${GREEN}✅ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        if [ "$warning_only" = "true" ]; then
            echo -e "${YELLOW}⚠️ WARNING${NC}"
            WARNING_TESTS=$((WARNING_TESTS + 1))
            return 1
        else
            echo -e "${RED}❌ FAIL${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi
}

run_command_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_output="$3"
    local warning_only="${4:-false}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "  Testing $test_name... "
    
    # Capture both output and exit code
    if output=$(eval "$test_command" 2>&1); then
        if [[ -n "$expected_output" ]] && echo "$output" | grep -qE "$expected_output"; then
            echo -e "${GREEN}✅ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        elif [[ -z "$expected_output" ]]; then
            echo -e "${GREEN}✅ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            if [ "$warning_only" = "true" ]; then
                echo -e "${YELLOW}⚠️ WARNING${NC} (Expected: $expected_output, Got: ${output:0:50}...)"
                WARNING_TESTS=$((WARNING_TESTS + 1))
            else
                echo -e "${RED}❌ FAIL${NC} (Expected: $expected_output, Got: ${output:0:50}...)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            return 1
        fi
    else
        if [ "$warning_only" = "true" ]; then
            echo -e "${YELLOW}⚠️ WARNING${NC} (Command failed: ${output:0:50}...)"
            WARNING_TESTS=$((WARNING_TESTS + 1))
        else
            echo -e "${RED}❌ FAIL${NC} (Command failed: ${output:0:50}...)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        return 1
    fi
}

echo ""
echo -e "${CYAN}🧪 Kubernetes the Hard Way - Full Deployment Test${NC}"
echo "=================================================="
echo "This comprehensive test will verify all components from infrastructure through etcd bootstrap"
echo ""

# Test 1: Prerequisites and Environment
echo -e "${BLUE}📋 Test Suite 1: Prerequisites and Environment${NC}"
echo "=============================================="

run_test "WSL environment" "grep -q microsoft /proc/version" "0" "true"
run_test "terraform command" "command -v terraform"
run_test "kubectl command" "command -v kubectl"
run_test "jq command" "command -v jq"
run_test "openssl command" "command -v openssl"
run_test "ssh command" "command -v ssh"
run_test "terraform.tfvars exists" "[ -f terraform.tfvars ]"

echo ""

# Test 2: Infrastructure State
echo -e "${BLUE}🏗️ Test Suite 2: Infrastructure State${NC}"
echo "===================================="

run_test "terraform state exists" "[ -f terraform.tfstate ]"
if [ -f terraform.tfstate ]; then
    run_test "terraform state not empty" "[ -s terraform.tfstate ]"
else
    echo -e "  ${YELLOW}⚠️ Terraform state not found. Infrastructure may not be deployed.${NC}"
    echo "  Skipping infrastructure-dependent tests..."
    echo ""
    echo -e "${RED}❌ DEPLOYMENT INCOMPLETE${NC}"
    echo "Please run 'make deploy' first to create the infrastructure."
    exit 1
fi

if [ -f terraform.tfstate ]; then
    # Test terraform outputs
    echo "  Checking terraform outputs..."
    
    # More flexible IP validation
    if CONTROLLER_PUB_TEST=$(terraform output -raw controller_public_ip 2>/dev/null) && [[ "$CONTROLLER_PUB_TEST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "  Testing controller public IP output... ${GREEN}✅ PASS${NC} ($CONTROLLER_PUB_TEST)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "  Testing controller public IP output... ${RED}❌ FAIL${NC} (Got: '$CONTROLLER_PUB_TEST')"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if CONTROLLER_PRIV_TEST=$(terraform output -raw controller_private_ip 2>/dev/null) && [[ "$CONTROLLER_PRIV_TEST" =~ ^10\.240\.0\. ]]; then
        echo -e "  Testing controller private IP output... ${GREEN}✅ PASS${NC} ($CONTROLLER_PRIV_TEST)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "  Testing controller private IP output... ${RED}❌ FAIL${NC} (Got: '$CONTROLLER_PRIV_TEST')"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if WORKER_TEST=$(terraform output -json worker_nodes 2>/dev/null) && echo "$WORKER_TEST" | grep -q "node-0"; then
        echo -e "  Testing worker nodes output... ${GREEN}✅ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "  Testing worker nodes output... ${RED}❌ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Get IPs for further testing
    CONTROLLER_PUBLIC_IP=$(terraform output -raw controller_public_ip 2>/dev/null || echo "")
    CONTROLLER_PRIVATE_IP=$(terraform output -raw controller_private_ip 2>/dev/null || echo "")
    WORKER_0_PUBLIC_IP=$(terraform output -json worker_nodes 2>/dev/null | jq -r '."node-0".public_ip' 2>/dev/null || echo "")
    WORKER_1_PUBLIC_IP=$(terraform output -json worker_nodes 2>/dev/null | jq -r '."node-1".public_ip' 2>/dev/null || echo "")
    
    echo "  Infrastructure IPs discovered:"
    echo "    Controller: $CONTROLLER_PUBLIC_IP (public), $CONTROLLER_PRIVATE_IP (private)"
    echo "    Worker 0: $WORKER_0_PUBLIC_IP"
    echo "    Worker 1: $WORKER_1_PUBLIC_IP"
fi

echo ""

# Test 3: SSH Connectivity
echo -e "${BLUE}🔑 Test Suite 3: SSH Connectivity${NC}"
echo "=================================="

BOOTSTRAP_KEY="$HOME/.ssh/kubernetes-hard-way.pem"
JUMPBOX_KEY="$HOME/.ssh/id_rsa"

run_test "bootstrap SSH key exists" "[ -f '$BOOTSTRAP_KEY' ]"
run_test "jumpbox SSH key exists" "[ -f '$JUMPBOX_KEY' ]"
run_test "bootstrap key permissions" "[ \$(stat -c %a '$BOOTSTRAP_KEY' 2>/dev/null) = '600' ]"
run_test "jumpbox key permissions" "[ \$(stat -c %a '$JUMPBOX_KEY' 2>/dev/null) = '600' ]"

if [ -n "$CONTROLLER_PUBLIC_IP" ] && [ -n "$WORKER_0_PUBLIC_IP" ] && [ -n "$WORKER_1_PUBLIC_IP" ]; then
    echo "  Testing SSH connectivity to instances..."
    
    # Test hostname resolution first
    run_test "server hostname resolution" "getent hosts server >/dev/null" "0" "true"
    run_test "node-0 hostname resolution" "getent hosts node-0 >/dev/null" "0" "true"
    run_test "node-1 hostname resolution" "getent hosts node-1 >/dev/null" "0" "true"
    
    # Test SSH connectivity with hostnames
    run_test "SSH to server as root" "timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@server 'echo test'" "0" "true"
    run_test "SSH to node-0 as root" "timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@node-0 'echo test'" "0" "true"
    run_test "SSH to node-1 as root" "timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@node-1 'echo test'" "0" "true"
    
    # Fallback IP-based tests if hostname tests fail
    if ! timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@server "echo test" >/dev/null 2>&1; then
        echo "    Fallback: Testing IP-based SSH connectivity..."
        if timeout 10 ssh -i "$BOOTSTRAP_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$CONTROLLER_PUBLIC_IP" 'echo test' >/dev/null 2>&1; then
            echo -e "    ${GREEN}✅ SSH to controller via IP works${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "    ${RED}❌ SSH to controller via IP failed${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        if timeout 10 ssh -i "$BOOTSTRAP_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$WORKER_0_PUBLIC_IP" 'echo test' >/dev/null 2>&1; then
            echo -e "    ${GREEN}✅ SSH to worker-0 via IP works${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "    ${RED}❌ SSH to worker-0 via IP failed${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        if timeout 10 ssh -i "$BOOTSTRAP_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$WORKER_1_PUBLIC_IP" 'echo test' >/dev/null 2>&1; then
            echo -e "    ${GREEN}✅ SSH to worker-1 via IP works${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "    ${RED}❌ SSH to worker-1 via IP failed${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi
fi

echo ""

# Test 4: Jumpbox Setup
echo -e "${BLUE}🖥️ Test Suite 4: Jumpbox Environment${NC}"
echo "==================================="

run_test "kubernetes-the-hard-way directory" "[ -d kubernetes-the-hard-way ]"
run_test "downloads directory" "[ -d kubernetes-the-hard-way/downloads ]"
run_test "kubectl in PATH" "which kubectl"

if [ -d "kubernetes-the-hard-way" ]; then
    cd kubernetes-the-hard-way
    
    # Test binary directories
    run_test "client binaries directory" "[ -d downloads/client ]"
    run_test "controller binaries directory" "[ -d downloads/controller ]"
    run_test "worker binaries directory" "[ -d downloads/worker ]"
    run_test "cni-plugins directory" "[ -d downloads/cni-plugins ]"
    
    # Test specific binaries
    run_test "kubectl binary" "[ -f downloads/client/kubectl ]"
    run_test "etcdctl binary" "[ -f downloads/client/etcdctl ]"
    run_test "etcd binary" "[ -f downloads/controller/etcd ]"
    run_test "kube-apiserver binary" "[ -f downloads/controller/kube-apiserver ]"
    run_test "kubelet binary" "[ -f downloads/worker/kubelet ]"
    run_test "kube-proxy binary" "[ -f downloads/worker/kube-proxy ]"
    
    # Test binary executability
    run_test "kubectl executable" "[ -x downloads/client/kubectl ]"
    run_test "etcd executable" "[ -x downloads/controller/etcd ]"
    run_test "kubelet executable" "[ -x downloads/worker/kubelet ]"
    
    cd ..
fi

echo ""

# Test 5: Compute Resources Setup
echo -e "${BLUE}🖥️ Test Suite 5: Compute Resources Setup${NC}"
echo "======================================="

run_test "machines.txt exists" "[ -f kubernetes-the-hard-way/machines.txt ]"

if [ -f "kubernetes-the-hard-way/machines.txt" ]; then
    cd kubernetes-the-hard-way
    
    # Test machines.txt content
    run_command_test "machines.txt has server entry" "cat machines.txt" "server.kubernetes.local"
    run_command_test "machines.txt has node-0 entry" "cat machines.txt" "node-0.kubernetes.local"
    run_command_test "machines.txt has node-1 entry" "cat machines.txt" "node-1.kubernetes.local"
    run_command_test "machines.txt has pod networks" "cat machines.txt" "10.200"
    
    echo "  Content of machines.txt:"
    cat machines.txt | sed 's/^/    /'
    
    cd ..
fi

# Test /etc/hosts configuration
run_command_test "/etc/hosts has server entry" "cat /etc/hosts" "server" "true"
run_command_test "/etc/hosts has node-0 entry" "cat /etc/hosts" "node-0" "true"
run_command_test "/etc/hosts has node-1 entry" "cat /etc/hosts" "node-1" "true"

echo ""

# Test 6: Certificate Generation
echo -e "${BLUE}🔐 Test Suite 6: PKI Certificates${NC}"
echo "================================"

if [ -d "kubernetes-the-hard-way" ]; then
    cd kubernetes-the-hard-way
    
    # Test CA files
    run_test "CA certificate exists" "[ -f ca.crt ]"
    run_test "CA private key exists" "[ -f ca.key ]"
    
    # Test component certificates
    certificates=("admin" "node-0" "node-1" "kube-proxy" "kube-scheduler" "kube-controller-manager" "kube-api-server" "service-accounts")
    
    for cert in "${certificates[@]}"; do
        run_test "$cert certificate exists" "[ -f ${cert}.crt ]"
        run_test "$cert private key exists" "[ -f ${cert}.key ]"
    done
    
    # Test certificate validity
    if [ -f ca.crt ] && [ -f admin.crt ]; then
        run_test "CA certificate is valid" "openssl x509 -in ca.crt -noout -text >/dev/null"
        run_test "admin certificate is valid" "openssl x509 -in admin.crt -noout -text >/dev/null"
        run_test "admin cert signed by CA" "openssl verify -CAfile ca.crt admin.crt >/dev/null"
    fi
    
    # Test certificate distribution to workers
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@node-0 'echo test' >/dev/null 2>&1; then
        echo "  Testing certificate distribution to workers..."
        run_test "CA cert on node-0" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-0 '[ -f /var/lib/kubelet/ca.crt ]'"
        run_test "kubelet cert on node-0" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-0 '[ -f /var/lib/kubelet/kubelet.crt ]'"
        run_test "kubelet key on node-0" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-0 '[ -f /var/lib/kubelet/kubelet.key ]'"
        
        run_test "CA cert on node-1" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-1 '[ -f /var/lib/kubelet/ca.crt ]'"
        run_test "kubelet cert on node-1" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-1 '[ -f /var/lib/kubelet/kubelet.crt ]'"
        run_test "kubelet key on node-1" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-1 '[ -f /var/lib/kubelet/kubelet.key ]'"
    fi
    
    # Test certificate distribution to controller
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@server 'echo test' >/dev/null 2>&1; then
        echo "  Testing certificate distribution to controller..."
        
        # Debug: Show what's actually in the controller home directory
        echo "    Debug: Files in controller home directory:"
        if controller_files=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'ls -la ~/' 2>/dev/null); then
            echo "$controller_files" | grep -E '\.(crt|key)' || echo "      No certificate files found"
        else
            echo "      Could not list controller home directory"
        fi
        
        # Check if certificates are in the home directory or in /var/lib/kubernetes/
        run_test "CA cert on controller (home)" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/ca.crt ] || [ -f /var/lib/kubernetes/ca.crt ]'" "0" "true"
        run_test "CA key on controller (home)" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/ca.key ] || [ -f /var/lib/kubernetes/ca.key ]'" "0" "true"
        run_test "kube-api-server cert on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/kube-api-server.crt ] || [ -f /var/lib/kubernetes/kube-api-server.crt ]'" "0" "true"
        run_test "kube-api-server key on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/kube-api-server.key ] || [ -f /var/lib/kubernetes/kube-api-server.key ]'" "0" "true"
        run_test "service-accounts cert on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/service-accounts.crt ] || [ -f /var/lib/kubernetes/service-accounts.crt ]'" "0" "true"
        run_test "service-accounts key on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/service-accounts.key ] || [ -f /var/lib/kubernetes/service-accounts.key ]'" "0" "true"
        
        # Check if certificates need to be distributed
        if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server "[ -f ~/ca.crt ] || [ -f /var/lib/kubernetes/ca.crt ]" 2>/dev/null; then
            echo -e "    ${YELLOW}⚠️ Certificates missing on controller. You may need to run:${NC}"
            echo "      make generate-certs"
            echo "      This will automatically distribute certificates to all nodes."
        fi
    else
        echo "  Cannot connect to controller, skipping certificate distribution tests..."
        TOTAL_TESTS=$((TOTAL_TESTS + 6))
        WARNING_TESTS=$((WARNING_TESTS + 6))
    fi
    
    cd ..
fi

echo ""

# Test 7: Configuration Files (Kubeconfigs)
echo -e "${BLUE}📝 Test Suite 7: Kubernetes Configuration Files${NC}"
echo "=============================================="

if [ -d "kubernetes-the-hard-way" ]; then
    cd kubernetes-the-hard-way
    
    # Test kubeconfig files
    kubeconfigs=("admin" "node-0" "node-1" "kube-proxy" "kube-controller-manager" "kube-scheduler")
    
    for config in "${kubeconfigs[@]}"; do
        run_test "$config kubeconfig exists" "[ -f ${config}.kubeconfig ]"
        if [ -f "${config}.kubeconfig" ]; then
            run_test "$config kubeconfig is valid YAML" "kubectl --kubeconfig=${config}.kubeconfig config view >/dev/null"
            run_command_test "$config kubeconfig has cluster" "kubectl --kubeconfig=${config}.kubeconfig config view" "kubernetes-the-hard-way"
        fi
    done
    
    # Test kubeconfig distribution to workers
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@node-0 'echo test' >/dev/null 2>&1; then
        echo "  Testing kubeconfig distribution to workers..."
        run_test "kubelet config on node-0" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-0 '[ -f /var/lib/kubelet/kubeconfig ]'"
        run_test "kube-proxy config on node-0" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-0 '[ -f /var/lib/kube-proxy/kubeconfig ]'"
        
        run_test "kubelet config on node-1" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-1 '[ -f /var/lib/kubelet/kubeconfig ]'"
        run_test "kube-proxy config on node-1" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-1 '[ -f /var/lib/kube-proxy/kubeconfig ]'"
    fi
    
    # Test kubeconfig distribution to controller
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@server 'echo test' >/dev/null 2>&1; then
        echo "  Testing kubeconfig distribution to controller..."
        run_test "admin config on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/admin.kubeconfig ]'"
        run_test "controller-manager config on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/kube-controller-manager.kubeconfig ] || [ -f /var/lib/kubernetes/kube-controller-manager.kubeconfig ]'"
        run_test "scheduler config on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/kube-scheduler.kubeconfig ] || [ -f /var/lib/kubernetes/kube-scheduler.kubeconfig ]'"
    fi
    
    cd ..
fi

echo ""

# Test 8: Data Encryption Configuration
echo -e "${BLUE}🔒 Test Suite 8: Data Encryption Configuration${NC}"
echo "============================================="

if [ -d "kubernetes-the-hard-way" ]; then
    cd kubernetes-the-hard-way
    
    # Test encryption config
    run_test "encryption config exists" "[ -f encryption-config.yaml ]"
    
    if [ -f encryption-config.yaml ]; then
        run_command_test "encryption config has correct kind" "cat encryption-config.yaml" "EncryptionConfiguration"
        run_command_test "encryption config has aescbc provider" "cat encryption-config.yaml" "aescbc"
        run_command_test "encryption config has secrets resource" "cat encryption-config.yaml" "secrets"
        run_test "encryption config is valid YAML" "python3 -c 'import yaml; yaml.safe_load(open(\"encryption-config.yaml\"))'" "0" "true"
    fi
    
    # Test encryption config distribution to controller
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@server 'echo test' >/dev/null 2>&1; then
        echo "  Testing encryption config distribution to controller..."
        run_test "encryption config on controller" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f ~/encryption-config.yaml ] || [ -f /var/lib/kubernetes/encryption-config.yaml ]'"
    fi
    
    cd ..
fi

echo ""

# Test 9: etcd Bootstrap
echo -e "${BLUE}🗄️ Test Suite 9: etcd Cluster Bootstrap${NC}"
echo "======================================"

if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@server 'echo test' >/dev/null 2>&1; then
    echo "  Testing etcd installation and configuration..."
    
    # Test etcd binaries
    run_test "etcd binary installed" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f /usr/local/bin/etcd ]'"
    run_test "etcdctl binary installed" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f /usr/local/bin/etcdctl ]'"
    run_test "etcd binary executable" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -x /usr/local/bin/etcd ]'"
    
    # Test etcd directories and certificates
    run_test "etcd config directory" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -d /etc/etcd ]'"
    run_test "etcd data directory" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -d /var/lib/etcd ]'"
    run_test "etcd CA cert in config" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f /etc/etcd/ca.crt ]'"
    run_test "etcd server cert in config" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f /etc/etcd/kube-api-server.crt ]'"
    run_test "etcd server key in config" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f /etc/etcd/kube-api-server.key ]'"
    
    # Test etcd systemd service
    run_test "etcd systemd unit exists" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server '[ -f /etc/systemd/system/etcd.service ]'"
    run_test "etcd service enabled" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'systemctl is-enabled etcd >/dev/null'"
    run_test "etcd service running" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'systemctl is-active etcd >/dev/null'"
    
    # Test etcd functionality
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'systemctl is-active etcd >/dev/null' 2>/dev/null; then
        echo "  Testing etcd cluster functionality..."
        run_test "etcd member list" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'etcdctl member list >/dev/null'"
        run_test "etcd cluster health" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'etcdctl endpoint health >/dev/null'" "0" "true"
        
        # Test basic etcd operations
        run_test "etcd put/get test" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'etcdctl put /test \"test-value\" && etcdctl get /test | grep -q \"test-value\"'"
        
        # Show etcd version and cluster info
        echo "  etcd cluster information:"
        if etcd_version=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'etcdctl version 2>/dev/null | head -1' 2>/dev/null); then
            echo "    Version: $etcd_version"
        fi
        if etcd_members=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'etcdctl member list 2>/dev/null' 2>/dev/null); then
            echo "    Members:"
            echo "$etcd_members" | sed 's/^/      /'
        fi
    else
        echo -e "    ${YELLOW}⚠️ etcd service not running, skipping functional tests${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️ Cannot connect to server, skipping etcd tests${NC}"
fi

echo ""

# Test 10: Overall System Health
echo -e "${BLUE}🏥 Test Suite 10: Overall System Health${NC}"
echo "====================================="

# Test hostname resolution from jumpbox
echo "  Testing hostname resolution and network connectivity..."
run_test "DNS resolution for server" "nslookup server >/dev/null || getent hosts server >/dev/null" "0" "true"
run_test "DNS resolution for node-0" "nslookup node-0 >/dev/null || getent hosts node-0 >/dev/null" "0" "true"
run_test "DNS resolution for node-1" "nslookup node-1 >/dev/null || getent hosts node-1 >/dev/null" "0" "true"

# Test network connectivity between nodes (if SSH works)
if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@server 'echo test' >/dev/null 2>&1; then
    echo "  Testing inter-node connectivity..."
    run_test "server can reach node-0" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'ping -c 1 node-0 >/dev/null'" "0" "true"
    run_test "server can reach node-1" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server 'ping -c 1 node-1 >/dev/null'" "0" "true"
    
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@node-0 'echo test' >/dev/null 2>&1; then
        run_test "node-0 can reach server" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-0 'ping -c 1 server >/dev/null'" "0" "true"
        run_test "node-0 can reach node-1" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@node-0 'ping -c 1 node-1 >/dev/null'" "0" "true"
    fi
fi

# Test system resources
if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@server 'echo test' >/dev/null 2>&1; then
    echo "  Testing system resources..."
    run_test "server disk space" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server \"df -h / | tail -1 | awk '{print \\\$5}' | sed 's/%//' | awk '{exit \\\$1 > 90}'\"" "0" "true"
    run_test "server memory available" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server \"free -m | grep '^Mem:' | awk '{exit \\\$7 < 100}'\"" "0" "true"
fi

echo ""

# Final Summary
echo -e "${CYAN}📊 TEST SUMMARY${NC}"
echo "================"
echo ""
echo "Total tests run: $TOTAL_TESTS"
echo -e "Tests passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Tests failed: ${RED}$FAILED_TESTS${NC}"
echo -e "Warnings: ${YELLOW}$WARNING_TESTS${NC}"
echo ""

# Calculate success rate
if [ $TOTAL_TESTS -gt 0 ]; then
    success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    echo "Success rate: ${success_rate}%"
    echo ""
fi

# Provide recommendations based on results
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL CRITICAL TESTS PASSED!${NC}"
    echo "Your Kubernetes the Hard Way deployment is ready through etcd bootstrap."
    echo ""
    echo -e "${BLUE}Next recommended steps:${NC}"
    echo "  1. make bootstrap-control-plane"
    echo "  2. make bootstrap-workers"
    echo "  3. make configure-kubectl"
    echo "  4. make setup-networking"
    echo "  5. make smoke-test"
    echo ""
elif [ $FAILED_TESTS -lt 5 ]; then
    echo -e "${YELLOW}⚠️ MOSTLY READY WITH MINOR ISSUES${NC}"
    echo "Most components are working correctly, but there are some minor issues."
    echo "Review the failed tests above and consider if they need attention."
    echo ""
    echo -e "${BLUE}You can likely proceed with:${NC}"
    echo "  make bootstrap-control-plane"
    echo ""
else
    echo -e "${RED}❌ SIGNIFICANT ISSUES DETECTED${NC}"
    echo "Multiple critical components have failed tests."
    echo "Please review and fix the failed tests before proceeding."
    echo ""
    echo -e "${BLUE}Recommended actions:${NC}"
    echo "  1. Review failed tests above"
    echo "  2. Check connectivity issues (try restarting WSL if hostname resolution failed)"
    echo "  3. Verify SSH keys and permissions"
    echo "  4. Re-run specific setup commands as needed"
    echo "  5. Re-run this test: make test-deployment"
fi

# WSL-specific guidance
if [ $WARNING_TESTS -gt 0 ] || [ $FAILED_TESTS -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}💡 WSL TROUBLESHOOTING TIPS:${NC}"
    echo "If you see hostname resolution or connectivity issues:"
    echo "  1. From Windows Command Prompt/PowerShell: wsl --shutdown"
    echo "  2. Wait 10 seconds, then restart your WSL terminal"
    echo "  3. Re-run: make test-deployment"
    echo ""
    echo "If SSH issues persist, use IP-based connections:"
    if [ -n "${CONTROLLER_PUBLIC_IP:-}" ]; then
        echo "  ssh -i ~/.ssh/kubernetes-hard-way.pem root@$CONTROLLER_PUBLIC_IP"
    fi
    if [ -n "${WORKER_0_PUBLIC_IP:-}" ]; then
        echo "  ssh -i ~/.ssh/kubernetes-hard-way.pem root@$WORKER_0_PUBLIC_IP"
    fi
    if [ -n "${WORKER_1_PUBLIC_IP:-}" ]; then
        echo "  ssh -i ~/.ssh/kubernetes-hard-way.pem root@$WORKER_1_PUBLIC_IP"
    fi
fi

echo ""

# Check if certificates need to be distributed and offer to do it automatically
if [ -d "kubernetes-the-hard-way" ] && [ -f "kubernetes-the-hard-way/ca.crt" ]; then
    cd kubernetes-the-hard-way
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@server 'echo test' >/dev/null 2>&1; then
        if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@server "[ -f ~/ca.crt ] || [ -f /var/lib/kubernetes/ca.crt ]" 2>/dev/null; then
            echo -e "${YELLOW}🔧 CERTIFICATE DISTRIBUTION NEEDED${NC}"
            echo "Certificates are generated but not distributed to the controller."
            echo ""
            echo -e "${BLUE}Would you like to distribute certificates now? (y/n)${NC}"
            read -r -n 1 response
            echo ""
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "Distributing certificates to controller..."
                if scp ca.key ca.crt kube-api-server.key kube-api-server.crt service-accounts.key service-accounts.crt root@server:~/ 2>/dev/null; then
                    echo -e "${GREEN}✅ Certificates distributed successfully!${NC}"
                    echo "You can now re-run the test to verify: make test-deployment"
                else
                    echo -e "${RED}❌ Failed to distribute certificates${NC}"
                    echo "Manual command: cd kubernetes-the-hard-way && scp ca.key ca.crt kube-api-server.key kube-api-server.crt service-accounts.key service-accounts.crt root@server:~/"
                fi
            fi
        fi
    fi
    cd ..
fi

# Exit with appropriate code
if [ $FAILED_TESTS -eq 0 ]; then
    exit 0
elif [ $FAILED_TESTS -lt 5 ]; then
    exit 1
else
    exit 2
fi