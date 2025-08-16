.PHONY: help deploy destroy status clean jumpbox-setup validate

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
	@echo ""
	@echo "Usage:"
	@echo "  1. Edit terraform.tfvars with your AWS settings"
	@echo "  2. Run: $(GREEN)make deploy$(NC)"
	@echo "  3. When done: $(RED)make destroy$(NC)"
	@echo ""

# Complete deployment pipeline
deploy:
	@echo ""
	@echo "$(GREEN)🚀 Starting Complete Kubernetes the Hard Way Deployment$(NC)"
	@echo "=================================================="
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
	
	@echo "$(GREEN)🎉 DEPLOYMENT COMPLETE!$(NC)"
	@echo "=================================================="
	@echo ""
	@echo "📊 Your infrastructure is ready! Run '$(YELLOW)make status$(NC)' to see connection details."
	@echo ""

# Destroy infrastructure
destroy:
	@echo ""
	@echo "$(RED)💥 Destroying Kubernetes Infrastructure$(NC)"
	@echo "============================================="
	@echo ""
	@echo "$(YELLOW)⚠️  WARNING: This will destroy ALL infrastructure!$(NC)"
	@echo ""
	@read -p "Are you sure you want to continue? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "$(RED)🗑️  Destroying infrastructure...$(NC)"; \
		terraform destroy -auto-approve; \
		if [ $$? -eq 0 ]; then \
			echo "$(GREEN)✅ Infrastructure destroyed successfully$(NC)"; \
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