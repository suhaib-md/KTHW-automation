# Kubernetes the Hard Way - AWS Terraform Automation

This project automates the infrastructure setup for [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) using Terraform on AWS.

## Architecture

The infrastructure includes:
- 1 Controller node (server) - `t3.medium` with 20GB storage
- 2 Worker nodes (node-0, node-1) - `t3.medium` with 20GB storage each  
- VPC with public/private subnets (10.240.0.0/24)
- Security groups for controller and worker nodes
- All running Debian 12 (bookworm)

## Prerequisites

1. **AWS CLI** - configured with appropriate credentials
2. **Terraform** >= 1.0
3. **jq** - for JSON processing
4. **WSL Debian** - as your jumpbox environment

## Quick Start

### 1. Initial Setup

```bash
# Make setup script executable and run it
chmod +x setup.sh
./setup.sh
```

This will:
- Check prerequisites
- Create SSH key pairs
- Set up terraform.tfvars
- Create directory structure

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
make init

# Review the deployment plan
make plan

# Deploy the infrastructure
make deploy
```

### 3. Setup Your WSL Jumpbox

After deployment, get the jumpbox setup commands:

```bash
make jumpbox-setup
```

This will display commands to:
- Update your WSL Debian system
- Clone the kubernetes-the-hard-way repository
- Download all required Kubernetes binaries
- Extract and organize the binaries
- Install kubectl locally

### 4. Check Infrastructure Status

```bash
make status
```

This shows:
- IP addresses of all nodes
- SSH connection commands
- Infrastructure overview

## Project Structure

```
.
├── main.tf                    # Root Terraform configuration
├── variables.tf               # Root variables
├── terraform.tfvars.example   # Example variables file
├── Makefile                   # Automation commands
├── setup.sh                   # Initial setup script
├── modules/
│   ├── vpc/                   # VPC module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security-groups/       # Security groups module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── ec2/                   # EC2 instances module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── cloud-init.yml
└── README.md
```

## Available Make Targets

| Command | Description |
|---------|-------------|
| `make help` | Show help message |
| `make init` | Initialize Terraform |
| `make plan` | Plan Terraform deployment |
| `make deploy` | Deploy infrastructure |
| `make destroy` | Destroy infrastructure |
| `make status` | Show current infrastructure status |
| `make jumpbox-setup` | Show jumpbox setup commands |
| `make clean` | Clean Terraform files |

## Network Configuration

- **VPC CIDR**: 10.240.0.0/24
- **Controller**: 10.240.0.10 (public subnet)
- **Worker 0**: 10.240.0.20 (private subnet, but with public IP)
- **Worker 1**: 10.240.0.21 (private subnet, but with public IP)

## Security Groups

### Controller Security Group
- SSH (22) - from anywhere
- Kubernetes API (6443) - from anywhere  
- etcd (2379-2380) - from VPC
- All internal VPC communication

### Worker Security Group  
- SSH (22) - from anywhere
- kubelet API (10250) - from VPC
- NodePort services (30000-32767) - from anywhere
- All internal VPC communication

## SSH Access

Connect to your instances:

```bash
# Controller
ssh -i ~/.ssh/kubernetes-hard-way.pem admin@<controller-public-ip>

# Workers
ssh -i ~/.ssh/kubernetes-hard-way.pem admin@<worker-0-public-ip>
ssh -i ~/.ssh/kubernetes-hard-way.pem admin@<worker-1-public-ip>
```

## Next Steps

After running `make deploy` and `make jumpbox-setup`:

1. Follow the jumpbox setup commands in your WSL Debian environment
2. Verify kubectl installation: `kubectl version --client`
3. Continue with the next steps in Kubernetes the Hard Way tutorial
4. Use `make status` anytime to get connection information

## Cleanup

When you're done with the tutorial:

```bash
make destroy
```

This will remove all AWS resources and clean up the infrastructure.

## Troubleshooting

### Common Issues

1. **AWS credentials not configured**:
   ```bash
   aws configure
   ```

2. **Key pair already exists error**:
   - Delete the existing key pair in AWS Console
   - Or use a different key name in terraform.tfvars

3. **Terraform initialization fails**:
   ```bash
   make clean
   make init
   ```

4. **SSH connection refused**:
   - Wait a few minutes for instances to fully boot
   - Check security group rules
   - Verify the correct private key is being used

### Getting Help

- Check AWS CloudTrail for detailed error messages
- Review Terraform state: `terraform show`
- Verify AWS permissions for EC2, VPC, and IAM actions

## Cost Considerations

- 3 x t3.medium instances (~$0.0416/hour each = ~$0.125/hour total)
- 60GB GP3 storage (~$4.80/month)
- Data transfer costs (minimal for tutorial usage)

**Estimated cost**: ~$20-30/month if left running continuously. 
**Remember to run `make destroy` when done!**