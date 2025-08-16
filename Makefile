.PHONY: help deploy destroy status clean jumpbox-setup validate cleanup-jumpbox full-cleanup setup-compute verify-compute test-deployment generate-certs

# Variables
PROJECT_NAME ?= kubernetes-hard-way
KEY_NAME ?= kubernetes-hard-way
AWS_REGION ?= us-west-2

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Default target
help:
	@echo ""
	@echo "🚀 Kubernetes the Hard Way - AWS Terraform Automation"
	@echo ""
	@echo "Available commands:"
	@echo "  $(GREEN)make deploy$(NC)        - 🚀 Complete deployment (setup + init + plan + apply + jumpbox)"
	@echo "  $(RED)make destroy$(NC)       - 💥 Destroy all infrastructure"
	@echo "  $(YELLOW)make status$(NC)        - 📊 Show infrastructure status and connection info"
	@echo "  $(YELLOW)make jumpbox-setup$(NC) - 🖥️  Setup WSL Debian jumpbox environment"
	@echo "  $(YELLOW)make validate$(NC)      - ✅ Validate prerequisites and configuration"
	@echo "  $(YELLOW)make clean$(NC)         - 🧹 Clean Terraform files and state"
	@echo "  $(YELLOW)make setup-compute$(NC) - 🖥️  Setup compute resources (machines.txt, SSH, hostnames)"
	@echo "  $(YELLOW)make verify-compute$(NC) - 🧪 Verify compute resources setup"
	@echo "  $(YELLOW)make generate-certs$(NC) - 🔐 Generate PKI certificates for Kubernetes components"
	@echo "  $(YELLOW)make test-deployment$(NC) - 🧪 Test complete deployment end-to-end"
	@echo "  $(YELLOW)make cleanup-jumpbox$(NC) - 🗑️  Clean up jumpbox files and binaries"
	@echo "  $(RED)make full-cleanup$(NC)  - 💥 Full cleanup (destroy + clean + cleanup-jumpbox)"
	@echo ""
	@echo "Usage:"
	@echo "  1. Edit terraform.tfvars with your AWS settings"
	@echo "  2. Run: $(GREEN)make deploy$(NC)"
	@echo "  3. Run: $(GREEN)make setup-compute$(NC)"
	@echo "  4. Run: $(GREEN)make generate-certs$(NC)"
	@echo "  5. When done: $(RED)make destroy$(NC) or $(RED)make full-cleanup$(NC)"
	@echo ""

# Complete deployment pipeline
deploy:
	@echo ""
	@echo "$(GREEN)🚀 Starting Complete Kubernetes the Hard Way Deployment$(NC)"
	@echo "=================================================="
	@echo "This will set up your complete Kubernetes infrastructure:"
	@echo "  • AWS Infrastructure (VPC, EC2, Security Groups)"  
	@echo "  • Jumpbox with Kubernetes binaries"
	@echo "  • Machine database and SSH configuration"
	@echo "  • Hostname resolution and connectivity"
	@echo ""
	
	@echo "$(YELLOW)📋 Step 1: Validating Prerequisites$(NC)"
	@./scripts/validate-prerequisites.sh
	@echo ""
	
	@echo "$(YELLOW)🔧 Step 2: Initial Setup$(NC)"
	@./scripts/setup.sh
	@echo ""
	
	@echo "$(YELLOW)⚙️  Step 3: Terraform Initialization$(NC)"
	@terraform init
	@echo ""
	
	@echo "$(YELLOW)📝 Step 4: Terraform Validation$(NC)"
	@terraform validate
	@if [ $$? -eq 0 ]; then \
		echo "$(GREEN)✅ Terraform configuration is valid$(NC)"; \
	else \
		echo "$(RED)❌ Terraform validation failed$(NC)"; \
		exit 1; \
	fi
	@echo ""
	
	@echo "$(YELLOW)📋 Step 5: Terraform Plan$(NC)"
	@terraform plan -out=tfplan
	@if [ $$? -eq 0 ]; then \
		echo "$(GREEN)✅ Terraform plan successful$(NC)"; \
	else \
		echo "$(RED)❌ Terraform plan failed$(NC)"; \
		exit 1; \
	fi
	@echo ""
	
	@echo "$(YELLOW)🏗️  Step 6: Terraform Apply$(NC)"
	@echo "Deploying infrastructure..."
	@terraform apply tfplan
	@if [ $$? -eq 0 ]; then \
		echo "$(GREEN)✅ Infrastructure deployed successfully$(NC)"; \
	else \
		echo "$(RED)❌ Infrastructure deployment failed$(NC)"; \
		exit 1; \
	fi
	@rm -f tfplan
	@echo ""
	
	@echo "$(YELLOW)🖥️  Step 7: Setting up Jumpbox$(NC)"
	@./scripts/jumpbox-setup.sh
	@echo ""
	
	@echo "$(YELLOW)🖥️  Step 8: Setting up Compute Resources$(NC)"
	@chmod +x scripts/setup-compute-resources.sh
	@./scripts/setup-compute-resources.sh
	@echo ""

	@echo "$(YELLOW)🖥️  Step 9: Generating PKI Certificates$(NC)"
	@chmod +x scripts/generate-certificates.sh
	@./scripts/generate-certificates.sh
	@echo ""
	
	@echo "$(GREEN)🎉 DEPLOYMENT COMPLETE!$(NC)"
	@echo "=================================================="
	@echo ""
	@echo "📊 Your Kubernetes infrastructure is fully configured!"
	@echo ""
	@echo "What's been set up:"
	@echo "  ✅ AWS Infrastructure (VPC, EC2 instances, Security Groups)"
	@echo "  ✅ Jumpbox environment with Kubernetes binaries"
	@echo "  ✅ Machine database and SSH configuration"  
	@echo "  ✅ Hostname resolution and connectivity"
	@echo "  ✅ PKI Certificate Authority and TLS certificates"
	@echo ""
	@echo "You can now connect to your machines:"
	@echo "  $(YELLOW)ssh root@server$(NC)   - Controller node"
	@echo "  $(YELLOW)ssh root@node-0$(NC)   - Worker node 0"
	@echo "  $(YELLOW)ssh root@node-1$(NC)   - Worker node 1"
	@echo ""
	@echo "$(GREEN)🚀 Ready for Kubernetes the Hard Way tutorial!$(NC)"
	@echo ""
	@echo "Next steps (in order):"
	@echo "  1. $(YELLOW)make generate-configs$(NC)   - 📝 Generate Kubernetes configuration files"
	@echo "  2. $(YELLOW)make generate-encryption$(NC) - 🔒 Generate data encryption config"
	@echo "  3. $(YELLOW)make bootstrap-etcd$(NC)     - 🗄️  Bootstrap etcd cluster"
	@echo "  4. $(YELLOW)make bootstrap-control$(NC)  - ⚙️  Bootstrap Kubernetes control plane"
	@echo "  5. $(YELLOW)make bootstrap-workers$(NC)  - 👷 Bootstrap Kubernetes worker nodes"
	@echo "  6. $(YELLOW)make configure-kubectl$(NC)  - 🎛️  Configure kubectl for remote access"
	@echo "  7. $(YELLOW)make setup-networking$(NC)   - 🌐 Configure pod networking (CNI)"
	@echo ""
	@echo "$(BLUE)💡 Tutorial Progress Tracking:$(NC)"
	@echo "  ✅ Lab 01: Prerequisites"
	@echo "  ✅ Lab 02: Provisioning Compute Resources" 
	@echo "  ✅ Lab 03: Provisioning a CA and Generating TLS Certificates"
	@echo "  ⏳ Lab 04: Generating Kubernetes Configuration Files"
	@echo "  ⏳ Lab 05: Generating the Data Encryption Config"
	@echo "  ⏳ Lab 06: Bootstrapping the etcd Cluster"
	@echo "  ⏳ Lab 07: Bootstrapping the Kubernetes Control Plane"
	@echo "  ⏳ Lab 08: Bootstrapping the Kubernetes Worker Nodes"
	@echo "  ⏳ Lab 09: Configuring kubectl for Remote Access"
	@echo "  ⏳ Lab 10: Provisioning Pod Network Routes"
	@echo "  ⏳ Lab 11: Deploying the DNS Cluster Add-on"
	@echo ""
	@echo "Quick verification commands:"
	@echo "  $(YELLOW)make status$(NC)              - 📊 Show infrastructure status"
	@echo "  $(YELLOW)make test-deployment$(NC)     - 🧪 Test complete setup end-to-end"
	@echo "  $(YELLOW)make verify-compute$(NC)      - 🧪 Verify compute resources only"
	@echo ""
	@echo "$(YELLOW)💡 Start with: make generate-configs$(NC)"
	@echo ""

# Destroy infrastructure
destroy:
	@echo ""
	@echo "$(RED)💥 Destroying Kubernetes Infrastructure$(NC)"
	@echo "============================================="
	@echo ""
	@echo "$(YELLOW)⚠️  WARNING: This will destroy ALL AWS infrastructure!$(NC)"
	@echo "$(YELLOW)⚠️  Local jumpbox files will NOT be removed.$(NC)"
	@echo ""
	@read -p "Are you sure you want to continue? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "$(RED)🗑️  Destroying infrastructure...$(NC)"; \
		terraform destroy -auto-approve; \
		if [ $$? -eq 0 ]; then \
			echo "$(GREEN)✅ Infrastructure destroyed successfully$(NC)"; \
			echo ""; \
			echo "$(YELLOW)💡 To also clean up jumpbox files, run: make cleanup-jumpbox$(NC)"; \
			echo "$(YELLOW)💡 For complete cleanup, run: make full-cleanup$(NC)"; \
		else \
			echo "$(RED)❌ Failed to destroy infrastructure$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)❌ Destruction cancelled$(NC)"; \
	fi
	@echo ""

# Show infrastructure status
status:
	@echo ""
	@echo "$(GREEN)📊 Infrastructure Status$(NC)"
	@echo "=========================="
	@echo ""
	@if [ ! -f terraform.tfstate ]; then \
		echo "$(RED)❌ No infrastructure found. Run 'make deploy' first.$(NC)"; \
		exit 1; \
	fi
	@terraform output -json | jq -r '
		"$(GREEN)Controller Node:$(NC)",
		"  🌐 Public IP:  " + .controller_public_ip.value,
		"  🏠 Private IP: " + .controller_private_ip.value,
		"",
		"$(GREEN)Worker Nodes:$(NC)",
		"  📦 node-0:",
		"    🌐 Public IP:  " + .worker_nodes.value."node-0".public_ip,
		"    🏠 Private IP: " + .worker_nodes.value."node-0".private_ip,
		"  📦 node-1:",
		"    🌐 Public IP:  " + .worker_nodes.value."node-1".public_ip,
		"    🏠 Private IP: " + .worker_nodes.value."node-1".private_ip,
		"",
		"$(GREEN)SSH Commands:$(NC)",
		"  🖥️  Controller: ssh -i ~/.ssh/$(KEY_NAME).pem admin@" + .controller_public_ip.value,
		"  🖥️  Worker 0:   ssh -i ~/.ssh/$(KEY_NAME).pem admin@" + .worker_nodes.value."node-0".public_ip,
		"  🖥️  Worker 1:   ssh -i ~/.ssh/$(KEY_NAME).pem admin@" + .worker_nodes.value."node-1".public_ip
	'
	@echo ""

# Setup jumpbox environment
jumpbox-setup:
	@echo ""
	@echo "$(GREEN)🖥️  Setting up WSL Debian Jumpbox$(NC)"
	@echo "================================="
	@echo ""
	@./scripts/jumpbox-setup.sh

# Validate prerequisites
validate:
	@echo ""
	@echo "$(GREEN)✅ Validating Prerequisites$(NC)"
	@echo "=============================="
	@echo ""
	@./scripts/validate-prerequisites.sh

# Clean Terraform files and state
clean:
	@echo ""
	@echo "$(YELLOW)🧹 Cleaning Terraform Files$(NC)"
	@echo "============================"
	@echo ""
	@echo "$(YELLOW)⚠️  This will remove all Terraform state and plans!$(NC)"
	@echo ""
	@read -p "Are you sure you want to continue? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "$(YELLOW)🗑️  Removing Terraform files...$(NC)"; \
		rm -rf .terraform/; \
		rm -f .terraform.lock.hcl; \
		rm -f terraform.tfstate*; \
		rm -f tfplan; \
		echo "$(GREEN)✅ Terraform files cleaned$(NC)"; \
	else \
		echo "$(YELLOW)❌ Cleaning cancelled$(NC)"; \
	fi
	@echo ""

# Clean up jumpbox files
cleanup-jumpbox:
	@echo ""
	@echo "$(YELLOW)🗑️  Cleaning Up Jumpbox Files$(NC)"
	@echo "==============================="
	@echo ""
	@./scripts/cleanup-jumpbox.sh

# Full cleanup (destroy + clean + cleanup-jumpbox)
full-cleanup:
	@echo ""
	@echo "$(RED)💥 Full Cleanup - Destroy Everything$(NC)"
	@echo "======================================"
	@echo ""
	@echo "$(YELLOW)⚠️  WARNING: This will:$(NC)"
	@echo "  - Destroy ALL AWS infrastructure"
	@echo "  - Remove ALL Terraform state files"
	@echo "  - Clean up ALL jumpbox files and binaries"
	@echo "  - Remove local SSH keys"
	@echo ""
	@read -p "Are you absolutely sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "$(RED)🗑️  Starting full cleanup...$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Step 1: Destroying infrastructure...$(NC)"; \
		terraform destroy -auto-approve || true; \
		echo ""; \
		echo "$(YELLOW)Step 2: Cleaning Terraform files...$(NC)"; \
		rm -rf .terraform/ || true; \
		rm -f .terraform.lock.hcl || true; \
		rm -f terraform.tfstate* || true; \
		rm -f tfplan || true; \
		echo ""; \
		echo "$(YELLOW)Step 3: Cleaning jumpbox files...$(NC)"; \
		./scripts/cleanup-jumpbox.sh || true; \
		echo ""; \
		echo "$(GREEN)🎉 Full cleanup complete!$(NC)"; \
		echo "You can now start fresh with 'make deploy'"; \
	else \
		echo "$(YELLOW)❌ Full cleanup cancelled$(NC)"; \
	fi
	@echo ""

# Setup compute resources
setup-compute:
	@echo ""
	@echo "$(GREEN)🖥️  Setting up Compute Resources$(NC)"
	@echo "==================================="
	@echo ""
	@chmod +x scripts/setup-compute-resources.sh
	@./scripts/setup-compute-resources.sh

# Verify compute resources setup
verify-compute:
	@echo ""
	@echo "$(YELLOW)🧪 Verifying Compute Resources$(NC)"
	@echo "============================"
	@echo ""
	@chmod +x scripts/verify-compute-setup.sh
	@./scripts/verify-compute-setup.sh

# Test complete deployment
test-deployment:
	@echo ""
	@echo "$(BLUE)🧪 Testing Full Deployment$(NC)"
	@echo "========================="
	@echo ""
	@chmod +x scripts/test-full-deployment.sh
	@./scripts/test-full-deployment.sh

# Generate PKI certificates
generate-certs:
	@echo ""
	@echo "$(GREEN)🔐 Generating PKI Certificates$(NC)"
	@echo "================================="
	@echo ""
	@chmod +x scripts/generate-certificates.sh
	@./scripts/generate-certificates.sh