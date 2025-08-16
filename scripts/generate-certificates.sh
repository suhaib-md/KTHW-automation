#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🔐 Kubernetes the Hard Way - PKI Certificate Generation${NC}"
echo "======================================================"
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

cd kubernetes-the-hard-way

# Check if ca.conf exists
if [ ! -f "ca.conf" ]; then
    echo -e "${RED}❌ ca.conf not found in kubernetes-the-hard-way directory${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Step 1: Reviewing CA configuration${NC}"
echo "Using ca.conf from kubernetes-the-hard-way repository:"
echo ""
head -20 ca.conf
echo "..."
echo "(Full configuration file available)"
echo ""

echo -e "${YELLOW}🔑 Step 2: Generating Certificate Authority${NC}"

# Clean up any existing certificates
echo "Cleaning up any existing certificates..."
rm -f *.crt *.key *.csr *.srl 2>/dev/null || true

# Generate CA private key and certificate (following KTHW exactly)
echo "Generating CA private key and self-signed certificate..."
{
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -sha512 -noenc \
    -key ca.key -days 3653 \
    -config ca.conf \
    -out ca.crt
}

echo ""
echo "Certificate Authority files created:"
ls -la ca.crt ca.key
echo ""

# Verify CA certificate
echo "CA Certificate details:"
openssl x509 -in ca.crt -text -noout | grep -A 2 "Subject:"
echo ""

echo -e "${YELLOW}🏭 Step 3: Generating Client and Server Certificates${NC}"

# Define certificates array (following KTHW exactly)
certs=(
  "admin" "node-0" "node-1"
  "kube-proxy" "kube-scheduler"
  "kube-controller-manager"
  "kube-api-server"
  "service-accounts"
)

echo "Generating certificates for: ${certs[*]}"
echo ""

# Generate certificates (following KTHW exactly)
for i in ${certs[*]}; do
  echo "  → Generating certificate for: $i"
  
  openssl genrsa -out "${i}.key" 4096

  openssl req -new -key "${i}.key" -sha256 \
    -config "ca.conf" -section ${i} \
    -out "${i}.csr"

  openssl x509 -req -days 3653 -in "${i}.csr" \
    -copy_extensions copyall \
    -sha256 -CA "ca.crt" \
    -CAkey "ca.key" \
    -CAcreateserial \
    -out "${i}.crt"
    
  echo -e "    ${GREEN}✅ ${i}.crt and ${i}.key created${NC}"
done

echo ""
echo -e "${GREEN}✅ All certificates generated successfully${NC}"
echo ""

# List generated files (following KTHW exactly)
echo "📋 Generated certificate files:"
ls -1 *.crt *.key *.csr | sort
echo ""

# Show certificate count
cert_count=$(ls -1 *.crt | wc -l)
key_count=$(ls -1 *.key | wc -l)
echo "Summary: $cert_count certificates, $key_count private keys"
echo ""

echo -e "${YELLOW}📦 Step 4: Distributing Client and Server Certificates${NC}"

# Verify connectivity before distribution
echo "Testing connectivity to nodes..."
for host in node-0 node-1 server; do
    if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$host" "echo 'Connection test'" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $host - Connected${NC}"
    else
        echo -e "  ${RED}❌ $host - Connection failed${NC}"
        echo "Cannot proceed with certificate distribution. Check connectivity."
        exit 1
    fi
done
echo ""

# Copy certificates to worker nodes (following KTHW exactly)
echo "Copying certificates to worker nodes (node-0, node-1)..."
for host in node-0 node-1; do
    echo "  → Processing $host..."
    
    # Create kubelet directory
    ssh root@${host} "mkdir -p /var/lib/kubelet/"
    echo "    Created /var/lib/kubelet/ directory"
    
    # Copy CA certificate
    scp ca.crt root@${host}:/var/lib/kubelet/
    echo "    Copied ca.crt"
    
    # Copy node-specific certificate and key
    scp ${host}.crt root@${host}:/var/lib/kubelet/kubelet.crt
    echo "    Copied ${host}.crt -> kubelet.crt"
    
    scp ${host}.key root@${host}:/var/lib/kubelet/kubelet.key
    echo "    Copied ${host}.key -> kubelet.key"
    
    echo -e "    ${GREEN}✅ $host certificate distribution complete${NC}"
done
echo ""

# Copy certificates to controller (following KTHW exactly)
echo "Copying certificates to controller (server)..."
scp \
  ca.key ca.crt \
  kube-api-server.key kube-api-server.crt \
  service-accounts.key service-accounts.crt \
  root@server:~/

echo -e "  ${GREEN}✅ Controller certificate distribution complete${NC}"
echo ""

echo -e "${YELLOW}🔍 Step 5: Verification${NC}"

# Verify certificates on worker nodes
echo "Verifying certificates on worker nodes..."
for host in node-0 node-1; do
    echo "  → Verifying $host..."
    
    # Check if files exist and have correct permissions
    file_check=$(ssh root@${host} "
        ls -la /var/lib/kubelet/ 2>/dev/null | grep -E '(ca.crt|kubelet.crt|kubelet.key)' | wc -l
    ")
    
    if [ "$file_check" -eq 3 ]; then
        echo -e "    ${GREEN}✅ All 3 certificate files present${NC}"
        
        # Verify certificate validity
        cert_valid=$(ssh root@${host} "
            openssl verify -CAfile /var/lib/kubelet/ca.crt /var/lib/kubelet/kubelet.crt >/dev/null 2>&1 && echo 'valid' || echo 'invalid'
        ")
        
        if [ "$cert_valid" = "valid" ]; then
            echo -e "    ${GREEN}✅ Certificate validation successful${NC}"
        else
            echo -e "    ${RED}❌ Certificate validation failed${NC}"
        fi
        
        # Show certificate subject
        subject=$(ssh root@${host} "openssl x509 -in /var/lib/kubelet/kubelet.crt -noout -subject")
        echo "    Subject: $subject"
        
    else
        echo -e "    ${RED}❌ Missing certificate files (found: $file_check/3)${NC}"
    fi
done
echo ""

# Verify certificates on controller
echo "Verifying certificates on controller (server)..."
file_check=$(ssh root@server "ls -la ~/ 2>/dev/null | grep -E '(ca.key|ca.crt|kube-api-server.key|kube-api-server.crt|service-accounts.key|service-accounts.crt)' | wc -l")

if [ "$file_check" -eq 6 ]; then
    echo -e "  ${GREEN}✅ All 6 certificate files present on controller${NC}"
    
    # Verify kube-api-server certificate
    cert_valid=$(ssh root@server "openssl verify -CAfile ~/ca.crt ~/kube-api-server.crt >/dev/null 2>&1 && echo 'valid' || echo 'invalid'")
    
    if [ "$cert_valid" = "valid" ]; then
        echo -e "  ${GREEN}✅ Kube-api-server certificate validation successful${NC}"
    else
        echo -e "  ${RED}❌ Kube-api-server certificate validation failed${NC}"
    fi
    
    # Show kube-api-server certificate subject and SANs
    echo "  Kube-api-server certificate details:"
    ssh root@server "openssl x509 -in ~/kube-api-server.crt -noout -subject"
    echo "  Subject Alternative Names:"
    ssh root@server "openssl x509 -in ~/kube-api-server.crt -noout -text | grep -A 5 'Subject Alternative Name'" | grep -v "Subject Alternative Name" || echo "    (None found)"
    
else
    echo -e "  ${RED}❌ Missing certificate files on controller (found: $file_check/6)${NC}"
fi
echo ""

# Clean up CSR files
echo -e "${YELLOW}🧹 Step 6: Cleanup${NC}"
echo "Removing certificate signing request (.csr) files..."
rm -f *.csr
echo "Removing certificate serial file..."
rm -f *.srl 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

echo -e "${GREEN}🎉 PKI CERTIFICATE GENERATION COMPLETE!${NC}"
echo "================================================="
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ Certificate Authority (CA) created${NC}"
echo -e "  ${GREEN}✅ 8 component certificates generated:${NC}"
for cert in ${certs[*]}; do
    echo "    • $cert"
done
echo ""
echo -e "  ${GREEN}✅ Worker node certificates distributed:${NC}"
echo "    • node-0: ca.crt, kubelet.crt, kubelet.key"
echo "    • node-1: ca.crt, kubelet.crt, kubelet.key"
echo ""
echo -e "  ${GREEN}✅ Controller certificates distributed:${NC}"
echo "    • server: ca.key, ca.crt, kube-api-server.key, kube-api-server.crt,"
echo "              service-accounts.key, service-accounts.crt"
echo ""
echo "Certificate files remaining in jumpbox:"
ls -1 *.crt *.key | sed 's/^/  • /'
echo ""
echo -e "${BLUE}Next step: Generate Kubernetes configuration files${NC}"
echo "Run: make generate-configs"
echo ""

cd ..
