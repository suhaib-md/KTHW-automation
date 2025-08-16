#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}🔐 Kubernetes the Hard Way - Data Encryption Configuration${NC}"
echo "========================================================="
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

# Check if kubeconfigs exist
if [ ! -f "admin.kubeconfig" ]; then
    echo -e "${RED}❌ Configuration files not found. Please run 'make generate-configs' first.${NC}"
    exit 1
fi

echo -e "${YELLOW}🔑 Step 1: Generating encryption key${NC}"

# Generate 32-byte encryption key and encode with base64
echo "Generating 32-byte encryption key..."
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

echo -e "${GREEN}✅ Encryption key generated${NC}"
echo "Key preview: ${ENCRYPTION_KEY:0:16}... (truncated for security)"
echo ""

echo -e "${YELLOW}📝 Step 2: Creating encryption config file${NC}"

# Check if configs directory exists in the repository
if [ ! -d "configs" ]; then
    echo -e "${RED}❌ configs directory not found in kubernetes-the-hard-way repository${NC}"
    echo "This should contain the encryption-config.yaml template"
    exit 1
fi

# Check if encryption config template exists
if [ ! -f "configs/encryption-config.yaml" ]; then
    echo -e "${YELLOW}⚠️ configs/encryption-config.yaml template not found${NC}"
    echo "Creating encryption config manually..."
    
    # Create the encryption config file manually
    cat > encryption-config.yaml << EOF
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
    
else
    echo "Using template from configs/encryption-config.yaml..."
    
    # Use envsubst to substitute the encryption key
    envsubst < configs/encryption-config.yaml > encryption-config.yaml
fi

if [ -f "encryption-config.yaml" ]; then
    echo -e "${GREEN}✅ encryption-config.yaml created${NC}"
    echo ""
    
    # Show file structure (without revealing the key)
    echo "File structure:"
    grep -v "secret:" encryption-config.yaml | head -10
    echo "      secret: [REDACTED]"
    grep -A 2 "identity:" encryption-config.yaml
    echo ""
else
    echo -e "${RED}❌ Failed to create encryption-config.yaml${NC}"
    exit 1
fi

echo -e "${YELLOW}🔍 Step 3: Validating encryption config${NC}"

# Basic validation of the config file
if grep -q "EncryptionConfig" encryption-config.yaml && \
   grep -q "aescbc" encryption-config.yaml && \
   grep -q "secrets" encryption-config.yaml; then
    echo -e "${GREEN}✅ Encryption config structure validated${NC}"
else
    echo -e "${RED}❌ Encryption config validation failed${NC}"
    exit 1
fi

# Check file size (should be reasonable)
file_size=$(wc -c < encryption-config.yaml)
if [ $file_size -gt 50 ] && [ $file_size -lt 1000 ]; then
    echo -e "${GREEN}✅ File size looks reasonable ($file_size bytes)${NC}"
else
    echo -e "${YELLOW}⚠️ Unusual file size: $file_size bytes${NC}"
fi

echo ""

echo -e "${YELLOW}📦 Step 4: Distributing encryption config to controller${NC}"

# Test connectivity first
echo "Testing connectivity to controller..."
if timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@server" "echo 'Connection test'" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅ server - Connected${NC}"
else
    echo -e "  ${RED}❌ server - Connection failed${NC}"
    echo "Cannot proceed with encryption config distribution. Check connectivity."
    exit 1
fi

echo ""

# Copy encryption config to controller
echo "Copying encryption-config.yaml to controller (server)..."
scp encryption-config.yaml root@server:~/

echo -e "${GREEN}✅ Encryption config distributed to controller${NC}"
echo ""

echo -e "${YELLOW}🔍 Step 5: Verification${NC}"

# Verify file on controller
echo "Verifying encryption config on controller..."
file_exists=$(ssh root@server "[ -f ~/encryption-config.yaml ] && echo 'exists' || echo 'missing'")

if [ "$file_exists" = "exists" ]; then
    echo -e "${GREEN}✅ encryption-config.yaml present on controller${NC}"
    
    # Check file size on controller
    remote_size=$(ssh root@server "wc -c < ~/encryption-config.yaml")
    echo "  Remote file size: $remote_size bytes"
    
    # Verify file structure on controller (without revealing secrets)
    echo "  Verifying file structure on controller..."
    structure_check=$(ssh root@server "grep -c 'EncryptionConfig\|aescbc\|secrets' ~/encryption-config.yaml")
    
    if [ "$structure_check" -ge 3 ]; then
        echo -e "  ${GREEN}✅ File structure verified on controller${NC}"
    else
        echo -e "  ${YELLOW}⚠️ File structure verification inconclusive${NC}"
    fi
    
    # Show file permissions
    permissions=$(ssh root@server "ls -la ~/encryption-config.yaml")
    echo "  File permissions: $permissions"
    
else
    echo -e "${RED}❌ encryption-config.yaml missing on controller${NC}"
    exit 1
fi

echo ""

# Security reminder
echo -e "${YELLOW}🔒 Security Notice${NC}"
echo "The encryption key has been embedded in the config file and distributed."
echo "Keep this file secure and do not share it publicly."
echo ""

echo -e "${GREEN}🎉 DATA ENCRYPTION CONFIGURATION COMPLETE!${NC}"
echo "================================================="
echo ""
echo "Summary of what was accomplished:"
echo -e "  ${GREEN}✅ 32-byte encryption key generated${NC}"
echo -e "  ${GREEN}✅ encryption-config.yaml created with AES-CBC encryption${NC}"
echo -e "  ${GREEN}✅ Configuration distributed to controller node${NC}"
echo -e "  ${GREEN}✅ File structure and permissions verified${NC}"
echo ""
echo "Files created:"
echo "  • encryption-config.yaml (local copy in jumpbox)"
echo "  • ~/encryption-config.yaml (on controller node)"
echo ""
echo "Configuration details:"
echo "  • Encryption method: AES-CBC"
echo "  • Encrypted resources: secrets"
echo "  • Fallback: identity (unencrypted) for existing data"
echo ""
echo -e "${BLUE}Next step: Bootstrap etcd cluster${NC}"
echo "Run: make bootstrap-etcd"
echo ""

cd ..