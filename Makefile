.PHONY: help deploy destroy status clean jumpbox-setup validate cleanup-jumpbox full-cleanup setup-compute verify-compute test-deployment generate-certs generate-configs generate-encryption bootstrap-etcd bootstrap-control-plane bootstrap-workers configure-kubectl setup-networking smoke-test

# Variables
PROJECT_NAME ?= kubernetes-hard-way
KEY_NAME ?= kubernetes-hard-way
AWS_REGION ?= us-west-2

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Default target
help:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🚀 Kubernetes the Hard Way - AWS Terraform Automation$(NC)"
	@/bin/echo ""
	@/bin/echo "Available commands:"
	@/bin/echo -e "  $(GREEN)make deploy$(NC)                - 🚀 Complete deployment (setup + init + plan + apply + jumpbox)"
	@/bin/echo -e "  $(RED)make destroy$(NC)               - 💥 Destroy all infrastructure"
	@/bin/echo -e "  $(YELLOW)make status$(NC)                - 📊 Show infrastructure status and connection info"
	@/bin/echo -e "  $(YELLOW)make jumpbox-setup$(NC)         - 🖥️  Setup WSL Debian jumpbox environment"
	@/bin/echo -e "  $(YELLOW)make validate$(NC)              - ✅ Validate prerequisites and configuration"
	@/bin/echo -e "  $(YELLOW)make clean$(NC)                 - 🧹 Clean Terraform files and state"
	@/bin/echo -e "  $(YELLOW)make setup-compute$(NC)         - 🖥️  Setup compute resources (machines.txt, SSH, hostnames)"
	@/bin/echo -e "  $(YELLOW)make verify-compute$(NC)        - 🧪 Verify compute resources setup"
	@/bin/echo -e "  $(YELLOW)make generate-certs$(NC)        - 🔐 Generate PKI certificates for Kubernetes components"
	@/bin/echo -e "  $(YELLOW)make generate-configs$(NC)      - 📝 Generate Kubernetes configuration files (kubeconfigs)"
	@/bin/echo -e "  $(YELLOW)make generate-encryption$(NC)   - 🔒 Generate data encryption configuration"
	@/bin/echo -e "  $(YELLOW)make bootstrap-etcd$(NC)        - 🗄️  Bootstrap etcd cluster"
	@/bin/echo -e "  $(YELLOW)make bootstrap-control-plane$(NC) - ⚙️  Bootstrap Kubernetes control plane"
	@/bin/echo -e "  $(YELLOW)make bootstrap-workers$(NC)     - 👷 Bootstrap Kubernetes worker nodes"
	@/bin/echo -e "  $(YELLOW)make configure-kubectl$(NC)     - 🎛️  Configure kubectl for remote access"
	@/bin/echo -e "  $(YELLOW)make setup-networking$(NC)      - 🌐 Setup pod network routes"
	@/bin/echo -e "  $(YELLOW)make test-deployment$(NC)       - 🧪 Test complete deployment end-to-end"
	@/bin/echo -e "  $(YELLOW)make cleanup-jumpbox$(NC)       - 🗑️  Clean up jumpbox files and binaries"
	@/bin/echo -e "  $(RED)make full-cleanup$(NC)          - 💥 Full cleanup (destroy + clean + cleanup-jumpbox)"
	@/bin/echo ""
	@/bin/echo "Usage:"
	@/bin/echo -e "  1. Edit terraform.tfvars with your AWS settings"
	@/bin/echo -e "  2. Run: $(GREEN)make deploy$(NC)"
	@/bin/echo -e "  3. When done: $(RED)make destroy$(NC) or $(RED)make full-cleanup$(NC)"
	@/bin/echo ""

# Complete deployment pipeline
deploy:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🚀 Starting Complete Kubernetes the Hard Way Deployment$(NC)"
	@/bin/echo "=================================================="
	@/bin/echo "This will set up your complete Kubernetes infrastructure:"
	@/bin/echo "  • AWS Infrastructure (VPC, EC2, Security Groups)"  
	@/bin/echo "  • Jumpbox with Kubernetes binaries"
	@/bin/echo "  • Machine database and SSH configuration"
	@/bin/echo "  • Hostname resolution and connectivity"
	@/bin/echo "  • PKI Certificate Authority and TLS certificates"
	@/bin/echo "  • Kubernetes configuration files (kubeconfigs)"
	@/bin/echo "  • Data encryption configuration"
	@/bin/echo "  • etcd cluster"
	@/bin/echo "  • Kubernetes control plane"
	@/bin/echo "  • Kubernetes worker nodes"
	@/bin/echo "  • kubectl remote access"
	@/bin/echo "  • Pod network routes"
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)📋 Step 1: Validating Prerequisites$(NC)"
	@./scripts/validate-prerequisites.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🔧 Step 2: Initial Setup$(NC)"
	@./scripts/setup.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)⚙️  Step 3: Terraform Initialization$(NC)"
	@terraform init
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)📝 Step 4: Terraform Validation$(NC)"
	@terraform validate
	@if [ $$? -eq 0 ]; then \
		/bin/echo -e "$(GREEN)✅ Terraform configuration is valid$(NC)"; \
	else \
		/bin/echo -e "$(RED)❌ Terraform validation failed$(NC)"; \
		exit 1; \
	fi
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)📋 Step 5: Terraform Plan$(NC)"
	@terraform plan -out=tfplan
	@if [ $$? -eq 0 ]; then \
		/bin/echo -e "$(GREEN)✅ Terraform plan successful$(NC)"; \
	else \
		/bin/echo -e "$(RED)❌ Terraform plan failed$(NC)"; \
		exit 1; \
	fi
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🏗️  Step 6: Terraform Apply$(NC)"
	@/bin/echo "Deploying infrastructure..."
	@terraform apply tfplan
	@if [ $$? -eq 0 ]; then \
		/bin/echo -e "$(GREEN)✅ Infrastructure deployed successfully$(NC)"; \
	else \
		/bin/echo -e "$(RED)❌ Infrastructure deployment failed$(NC)"; \
		exit 1; \
	fi
	@rm -f tfplan
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🖥️  Step 7: Setting up Jumpbox$(NC)"
	@./scripts/jumpbox-setup.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🖥️  Step 8: Setting up Compute Resources$(NC)"
	@chmod +x scripts/setup-compute-resources.sh
	@./scripts/setup-compute-resources.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🔐 Step 9: Generating PKI Certificates$(NC)"
	@chmod +x scripts/generate-certificates.sh
	@./scripts/generate-certificates.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)📝 Step 10: Generating Kubernetes Configuration Files$(NC)"
	@chmod +x scripts/generate-configs.sh
	@./scripts/generate-configs.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🔒 Step 11: Generating Data Encryption Configuration$(NC)"
	@chmod +x scripts/generate-encryption.sh
	@./scripts/generate-encryption.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🗄️  Step 12: Bootstrapping etcd Cluster$(NC)"
	@chmod +x scripts/bootstrap-etcd.sh
	@./scripts/bootstrap-etcd.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)⚙️  Step 13: Bootstrapping Kubernetes Control Plane$(NC)"
	@chmod +x scripts/bootstrap-control-plane.sh
	@./scripts/bootstrap-control-plane.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)👷 Step 14: Bootstrapping Kubernetes Worker Nodes$(NC)"
	@chmod +x scripts/bootstrap-workers.sh
	@./scripts/bootstrap-workers.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🎛️  Step 15: Configuring kubectl for Remote Access$(NC)"
	@chmod +x scripts/configure-kubectl.sh
	@./scripts/configure-kubectl.sh
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🌐 Step 16: Setting up Pod Network Routes$(NC)"
	@chmod +x scripts/setup-networking.sh
	@./scripts/setup-networking.sh
	@/bin/echo -e "$(YELLOW)🧪 Step 17:Running Kubernetes Cluster Smoke Tests$(NC)"
	@chmod +x scripts/smoke-test.sh
	@./scripts/smoke-test.sh	
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🎉 COMPLETE DEPLOYMENT SUCCESSFUL!$(NC)"
	@/bin/echo "=================================================="
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)📊 Your Kubernetes cluster is fully operational!$(NC)"
	@/bin/echo ""
	@/bin/echo "What's been set up:"
	@/bin/echo -e "  ✅ AWS Infrastructure (VPC, EC2 instances, Security Groups)"
	@/bin/echo -e "  ✅ Jumpbox environment with Kubernetes binaries"
	@/bin/echo -e "  ✅ Machine database and SSH configuration"  
	@/bin/echo -e "  ✅ Hostname resolution and connectivity"
	@/bin/echo -e "  ✅ PKI Certificate Authority and TLS certificates"
	@/bin/echo -e "  ✅ Kubernetes configuration files (kubeconfigs)"
	@/bin/echo -e "  ✅ Data encryption configuration"
	@/bin/echo -e "  ✅ etcd cluster"
	@/bin/echo -e "  ✅ Kubernetes control plane"
	@/bin/echo -e "  ✅ Kubernetes worker nodes"
	@/bin/echo -e "  ✅ kubectl remote access"
	@/bin/echo -e "  ✅ Pod network routes"
	@/bin/echo ""
	@/bin/echo "You can now connect to your machines:"
	@/bin/echo -e "  $(YELLOW)ssh root@server$(NC)   - Controller node"
	@/bin/echo -e "  $(YELLOW)ssh root@node-0$(NC)   - Worker node 0"
	@/bin/echo -e "  $(YELLOW)ssh root@node-1$(NC)   - Worker node 1"
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🚀 Kubernetes the Hard Way tutorial is COMPLETE!$(NC)"
	@/bin/echo ""
	@/bin/echo -e "$(BLUE)💡 Tutorial Progress Tracking:$(NC)"
	@/bin/echo -e "  ✅ Lab 01: Prerequisites"
	@/bin/echo -e "  ✅ Lab 02: Provisioning Compute Resources" 
	@/bin/echo -e "  ✅ Lab 03: Provisioning a CA and Generating TLS Certificates"
	@/bin/echo -e "  ✅ Lab 04: Generating Kubernetes Configuration Files"
	@/bin/echo -e "  ✅ Lab 05: Generating the Data Encryption Config"
	@/bin/echo -e "  ✅ Lab 06: Bootstrapping the etcd Cluster"
	@/bin/echo -e "  ✅ Lab 07: Bootstrapping the Kubernetes Control Plane"
	@/bin/echo -e "  ✅ Lab 08: Bootstrapping the Kubernetes Worker Nodes"
	@/bin/echo -e "  ✅ Lab 09: Configuring kubectl for Remote Access"
	@/bin/echo -e "  ✅ Lab 10: Provisioning Pod Network Routes"
	@/bin/echo ""
	@/bin/echo "Useful commands:"
	@/bin/echo -e "  $(YELLOW)make status$(NC)                  - 📊 Show infrastructure status"
	@/bin/echo -e "  $(YELLOW)make test-deployment$(NC)         - 🧪 Test complete setup end-to-end"
	@/bin/echo -e "  $(YELLOW)kubectl get nodes$(NC)            - 🔍 Check cluster nodes"
	@/bin/echo -e "  $(YELLOW)kubectl get componentstatuses$(NC) - 🔍 Check cluster health"
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)💡 Your Kubernetes cluster is ready for workloads!$(NC)"
	@/bin/echo ""

# Destroy infrastructure
destroy:
	@/bin/echo ""
	@/bin/echo -e "$(RED)💥 Destroying Kubernetes Infrastructure$(NC)"
	@/bin/echo "============================================="
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)⚠️  WARNING: This will destroy ALL AWS infrastructure!$(NC)"
	@/bin/echo -e "$(YELLOW)⚠️  Local jumpbox files will NOT be removed.$(NC)"
	@/bin/echo ""
	@bash -c 'read -p "Are you sure you want to continue? (yes/no): " confirm; \
		confirm=$$(echo "$$confirm" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$$//" -e "s/\r//"); \
		/bin/echo "Debug: confirm='\''$$confirm'\''"; \
		if [ "$$confirm" = "yes" ]; then \
			/bin/echo -e "$(RED)🗑️  Starting destruction...$(NC)"; \
			terraform destroy -auto-approve; \
		else \
			/bin/echo -e "$(YELLOW)❌ Destruction cancelled$(NC)"; \
			exit 1; \
		fi'
	@/bin/echo ""

# Show infrastructure status
status:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)📊 Infrastructure Status$(NC)"
	@/bin/echo "=========================="
	@/bin/echo ""
	@if [ ! -f terraform.tfstate ]; then \
		/bin/echo -e "$(RED)❌ No infrastructure found. Run 'make deploy' first.$(NC)"; \
		exit 1; \
	fi
	@CONTROLLER_PUBLIC_IP=$$(terraform output -raw controller_public_ip); \
	CONTROLLER_PRIVATE_IP=$$(terraform output -raw controller_private_ip); \
	WORKER_0_PUBLIC_IP=$$(terraform output -json worker_nodes | jq -r '."node-0".public_ip'); \
	WORKER_0_PRIVATE_IP=$$(terraform output -json worker_nodes | jq -r '."node-0".private_ip'); \
	WORKER_1_PUBLIC_IP=$$(terraform output -json worker_nodes | jq -r '."node-1".public_ip'); \
	WORKER_1_PRIVATE_IP=$$(terraform output -json worker_nodes | jq -r '."node-1".private_ip'); \
	/bin/echo -e "$(GREEN)Controller Node:$(NC)"; \
	/bin/echo "  🌐 Public IP:  $$CONTROLLER_PUBLIC_IP"; \
	/bin/echo "  🏠 Private IP: $$CONTROLLER_PRIVATE_IP"; \
	/bin/echo ""; \
	/bin/echo -e "$(GREEN)Worker Nodes:$(NC)"; \
	/bin/echo "  📦 node-0:"; \
	/bin/echo "    🌐 Public IP:  $$WORKER_0_PUBLIC_IP"; \
	/bin/echo "    🏠 Private IP: $$WORKER_0_PRIVATE_IP"; \
	/bin/echo "  📦 node-1:"; \
	/bin/echo "    🌐 Public IP:  $$WORKER_1_PUBLIC_IP"; \
	/bin/echo "    🏠 Private IP: $$WORKER_1_PRIVATE_IP"; \
	/bin/echo ""; \
	/bin/echo -e "$(GREEN)SSH Commands:$(NC)"; \
	/bin/echo "  🖥️  Controller: ssh -i ~/.ssh/$(KEY_NAME).pem admin@$$CONTROLLER_PUBLIC_IP"; \
	/bin/echo "  🖥️  Worker 0:   ssh -i ~/.ssh/$(KEY_NAME).pem admin@$$WORKER_0_PUBLIC_IP"; \
	/bin/echo "  🖥️  Worker 1:   ssh -i ~/.ssh/$(KEY_NAME).pem admin@$$WORKER_1_PUBLIC_IP"
	@/bin/echo ""

# Setup jumpbox environment
jumpbox-setup:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🖥️  Setting up WSL Debian Jumpbox$(NC)"
	@/bin/echo "================================="
	@/bin/echo ""
	@./scripts/jumpbox-setup.sh

# Validate prerequisites
validate:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)✅ Validating Prerequisites$(NC)"
	@/bin/echo "=============================="
	@/bin/echo ""
	@./scripts/validate-prerequisites.sh

# Clean Terraform files and state
clean:
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🧹 Cleaning Terraform Files$(NC)"
	@/bin/echo "============================"
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)⚠️  This will remove all Terraform state and plans!$(NC)"
	@/bin/echo ""
	@bash -c 'read -p "Are you sure you want to continue? (yes/no): " confirm; \
		confirm=$$(echo "$$confirm" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$$//" -e "s/\r//"); \
		/bin/echo "Debug: confirm='\''$$confirm'\''"; \
		if [ "$$confirm" = "yes" ]; then \
			/bin/echo -e "$(YELLOW)🗑️  Removing Terraform files...$(NC)"; \
			rm -rf .terraform/ || true; \
			rm -f .terraform.lock.hcl || true; \
			rm -f terraform.tfstate* || true; \
			rm -f tfplan || true; \
			/bin/echo -e "$(GREEN)✅ Terraform files cleaned$(NC)"; \
		else \
			/bin/echo -e "$(YELLOW)❌ Cleaning cancelled$(NC)"; \
		fi'
	@/bin/echo ""

# Clean up jumpbox files
cleanup-jumpbox:
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🗑️  Cleaning Up Jumpbox Files$(NC)"
	@/bin/echo "==============================="
	@/bin/echo ""
	@./scripts/cleanup-jumpbox.sh

# Full cleanup (destroy + clean + cleanup-jumpbox + kubernetes files)
full-cleanup:
	@/bin/echo ""
	@/bin/echo "💥 Full Cleanup - Destroy Everything"
	@/bin/echo "======================================"
	@/bin/echo ""
	@/bin/echo "⚠️  WARNING: This will:"
	@/bin/echo "  - Destroy ALL AWS infrastructure"
	@/bin/echo "  - Remove ALL Terraform state files"
	@/bin/echo "  - Clean up ALL jumpbox files and binaries"
	@/bin/echo "  - Remove local SSH keys"
	@/bin/echo "  - Remove ALL Kubernetes certificates and configs"
	@/bin/echo "  - Remove machines.txt and generated configs"
	@/bin/echo "  - Remove kubectl configurations"
	@/bin/echo ""
	@bash -c 'read -p "Are you absolutely sure? (yes/no): " confirm; \
		confirm=$$(echo "$$confirm" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$$//" -e "s/\r//"); \
		echo "Debug: confirm='\''$$confirm'\''"; \
		if [ "$$confirm" = "yes" ]; then \
			echo -e "🗑️  Starting full cleanup..."; \
			echo ""; \
			echo -e "Step 1: Destroying infrastructure..."; \
			terraform destroy -auto-approve || true; \
			echo ""; \
			echo -e "Step 2: Cleaning Terraform files..."; \
			rm -rf .terraform/ || true; \
			rm -f .terraform.lock.hcl || true; \
			rm -f terraform.tfstate* || true; \
			rm -f tfplan || true; \
			echo ""; \
			echo -e "\033[1;33mStep 3: Cleaning jumpbox files...\033[0m"; \
			./scripts/cleanup-jumpbox.sh || true; \
			echo ""; \
			echo -e "\033[1;33mStep 4: Cleaning Kubernetes files...\033[0m"; \
			rm -rf pki/ || true; \
			rm -f machines.txt || true; \
			rm -f *.kubeconfig || true; \
			rm -f admin.kubeconfig || true; \
			rm -f kube-controller-manager.kubeconfig || true; \
			rm -f kube-proxy.kubeconfig || true; \
			rm -f kube-scheduler.kubeconfig || true; \
			rm -f node-*.kubeconfig || true; \
			rm -f encryption-config.yaml || true; \
			rm -rf ~/.kube/config || true; \
			echo -e "\033[1;32m✅ Kubernetes files cleaned\033[0m"; \
			echo ""; \
			echo -e "\033[1;32m🎉 Full cleanup complete!\033[0m"; \
			echo "You can now start fresh with '\''make deploy'\''"; \
		else \
			echo -e "\033[1;33m❌ Full cleanup cancelled\033[0m"; \
		fi'
	@/bin/echo ""

# Setup compute resources
setup-compute:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🖥️  Setting up Compute Resources$(NC)"
	@/bin/echo "==================================="
	@/bin/echo ""
	@chmod +x scripts/setup-compute-resources.sh
	@./scripts/setup-compute-resources.sh

# Verify compute resources setup
verify-compute:
	@/bin/echo ""
	@/bin/echo -e "$(YELLOW)🧪 Verifying Compute Resources$(NC)"
	@/bin/echo "============================"
	@/bin/echo ""
	@chmod +x scripts/verify-compute-setup.sh
	@./scripts/verify-compute-setup.sh

# Test complete deployment
test-deployment:
	@/bin/echo ""
	@/bin/echo -e "$(BLUE)🧪 Testing Full Deployment$(NC)"
	@/bin/echo "========================="
	@/bin/echo ""
	@chmod +x scripts/test-full-deployment.sh
	@./scripts/test-full-deployment.sh

# Generate PKI certificates
generate-certs:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🔐 Generating PKI Certificates$(NC)"
	@/bin/echo "================================="
	@/bin/echo ""
	@chmod +x scripts/generate-certificates.sh
	@./scripts/generate-certificates.sh

# Generate Kubernetes configuration files
generate-configs:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)📝 Generating Kubernetes Configuration Files$(NC)"
	@/bin/echo "=============================================="
	@/bin/echo ""
	@chmod +x scripts/generate-configs.sh
	@./scripts/generate-configs.sh

# Generate data encryption configuration
generate-encryption:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🔒 Generating Data Encryption Configuration$(NC)"
	@/bin/echo "=============================================="
	@/bin/echo ""
	@chmod +x scripts/generate-encryption.sh
	@./scripts/generate-encryption.sh

# Bootstrap etcd cluster
bootstrap-etcd:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🗄️  Bootstrapping etcd Cluster$(NC)"
	@/bin/echo "================================="
	@/bin/echo ""
	@chmod +x scripts/bootstrap-etcd.sh
	@./scripts/bootstrap-etcd.sh

# Bootstrap Kubernetes control plane
bootstrap-control-plane:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)⚙️  Bootstrapping Kubernetes Control Plane$(NC)"
	@/bin/echo "=============================================="
	@/bin/echo ""
	@chmod +x scripts/bootstrap-control-plane.sh
	@./scripts/bootstrap-control-plane.sh

# Bootstrap Kubernetes worker nodes
bootstrap-workers:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)👷 Bootstrapping Kubernetes Worker Nodes$(NC)"
	@/bin/echo "============================================"
	@/bin/echo ""
	@chmod +x scripts/bootstrap-workers.sh
	@./scripts/bootstrap-workers.sh

# Configure kubectl for remote access
configure-kubectl:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🎛️  Configuring kubectl for Remote Access$(NC)"
	@/bin/echo "==============================================="
	@/bin/echo ""
	@chmod +x scripts/configure-kubectl.sh
	@./scripts/configure-kubectl.sh

# Setup pod network routes
setup-networking:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🌐 Setting up Pod Network Routes$(NC)"
	@/bin/echo "===================================="
	@/bin/echo ""
	@chmod +x scripts/setup-networking.sh
	@./scripts/setup-networking.sh

# Smoke test
smoke-test:
	@/bin/echo ""
	@/bin/echo -e "$(GREEN)🧪 Running Kubernetes Cluster Smoke Tests$(NC)"
	@/bin/echo "============================================="
	@/bin/echo ""
	@chmod +x scripts/smoke-test.sh
	@./scripts/smoke-test.sh
