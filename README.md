# Kubernetes the Hard Way - AWS Terraform Automation

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A5%201.0-blue)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-orange)](https://aws.amazon.com/)

A fully automated Terraform implementation of [Kelsey Hightower's "Kubernetes the Hard Way"](https://github.com/kelseyhightower/kubernetes-the-hard-way) tutorial, designed for learning Kubernetes fundamentals by building a cluster from scratch on AWS.

## 🎯 Project Overview

This project automates the entire "Kubernetes the Hard Way" tutorial using Terraform and shell scripts, providing:

- **Complete Infrastructure Automation**: AWS VPC, EC2 instances, Security Groups, and networking
- **WSL Debian Jumpbox Setup**: Automated development environment configuration
- **Full Kubernetes Cluster**: From PKI certificates to working worker nodes
- **Educational Focus**: Preserves the learning experience while eliminating tedious manual tasks

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC (10.240.0.0/24)             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   Controller    │  │    Worker 0     │  │    Worker 1     │ │
│  │     (server)    │  │    (node-0)     │  │    (node-1)     │ │
│  │                 │  │                 │  │                 │ │
│  │ • kube-apiserver│  │ • kubelet       │  │ • kubelet       │ │
│  │ • etcd          │  │ • kube-proxy    │  │ • kube-proxy    │ │
│  │ • kube-scheduler│  │ • containerd    │  │ • containerd    │ │
│  │ • kube-ctrl-mgr │  │ • runc          │  │ • runc          │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                │
│  Pod Networks: 10.200.0.0/24 (node-0) | 10.200.1.0/24 (node-1)│
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Features

### Infrastructure Automation
- **AWS Resources**: VPC, subnets, security groups, EC2 instances
- **Automatic SSH Key Management**: Generates and configures SSH keys
- **Network Security**: Properly configured security groups for Kubernetes components
- **Cost Optimized**: Uses t3.medium instances for learning purposes

### Kubernetes Components
- **PKI Infrastructure**: Complete certificate authority and TLS certificates
- **etcd Cluster**: Distributed key-value store for Kubernetes
- **Control Plane**: API server, controller manager, and scheduler
- **Worker Nodes**: kubelet, kube-proxy, and container runtime
- **Pod Networking**: Inter-node pod communication routes
- **RBAC**: Role-based access control configuration

### Development Experience
- **Single Command Deployment**: `make deploy` sets up everything
- **WSL Integration**: Optimized for Windows Subsystem for Linux
- **Educational Preservation**: Maintains the learning objectives of the original tutorial
- **Comprehensive Validation**: Automated testing and verification at each step

## 📋 Prerequisites

### Required Software
- **Windows 11** with WSL2 enabled
- **WSL Debian** distribution
- **Terraform** ≥ 1.0
- **AWS CLI** configured with appropriate credentials
- **jq** for JSON processing
- **OpenSSL** for certificate generation

### Required Skills
- Basic understanding of Kubernetes concepts
- AWS fundamentals (VPC, EC2, Security Groups)
- Command line proficiency
- SSH key management

### AWS Requirements
- AWS account with programmatic access
- IAM user with sufficient permissions:
  - EC2 full access
  - VPC management
  - IAM role creation (for EC2 instances)

## 🛠️ Installation & Setup

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/kubernetes-hard-way-terraform.git
cd kubernetes-hard-way-terraform
```

### 2. Configure AWS Credentials
```bash
# Using AWS CLI
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

### 3. Install Dependencies (WSL Debian)
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y terraform awscli jq openssl curl wget unzip

# Verify installations
terraform version
aws --version
jq --version
```

### 4. Configure Project Settings
```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration file
nano terraform.tfvars
```

**Example terraform.tfvars:**
```hcl
aws_region    = "us-west-2"
project_name  = "kubernetes-hard-way"
vpc_cidr      = "10.240.0.0/24"
instance_type = "t3.medium"
key_name      = "kubernetes-hard-way"

common_tags = {
  Project     = "kubernetes-hard-way"
  Environment = "learning"
  ManagedBy   = "terraform"
  Owner       = "your-name"
}
```

## 🚀 Quick Start

### Complete Deployment
```bash
# Single command deployment (recommended)
make deploy
```

This command will:
1. Validate prerequisites
2. Initialize Terraform
3. Deploy AWS infrastructure
4. Set up WSL jumpbox environment
5. Configure compute resources and SSH
6. Generate PKI certificates
7. Create Kubernetes configuration files
8. Bootstrap etcd cluster
9. Bootstrap Kubernetes control plane
10. Bootstrap worker nodes
11. Configure kubectl access
12. Set up pod networking
13. Run smoke tests

### Step-by-Step Deployment (Advanced)
```bash
# Individual steps for learning/debugging
make validate                    # Check prerequisites
make jumpbox-setup              # Setup WSL environment
make setup-compute              # Configure machines and SSH
make generate-certs             # Generate TLS certificates
make generate-configs           # Create kubeconfig files
make generate-encryption        # Setup data encryption
make bootstrap-etcd             # Start etcd cluster
make bootstrap-control-plane    # Start Kubernetes control plane
make bootstrap-workers          # Start worker nodes
make configure-kubectl          # Setup remote access
make setup-networking           # Configure pod networks
make smoke-test                 # Verify cluster
```

## 📊 Usage Examples

### Check Infrastructure Status
```bash
make status
```

### Connect to Cluster Nodes
```bash
# Controller node
ssh root@server

# Worker nodes
ssh root@node-0
ssh root@node-1
```

### Verify Cluster Health
```bash
# From jumpbox (after setup)
cd kubernetes-the-hard-way
kubectl get nodes --kubeconfig admin.kubeconfig
kubectl get componentstatuses --kubeconfig admin.kubeconfig

# From controller node
ssh root@server 'kubectl get nodes --kubeconfig admin.kubeconfig'
```

### Deploy Sample Application
```bash
# Create a test deployment
ssh root@server << 'EOF'
kubectl create deployment nginx --image=nginx --kubeconfig admin.kubeconfig
kubectl expose deployment nginx --port=80 --kubeconfig admin.kubeconfig
kubectl get pods,services --kubeconfig admin.kubeconfig
EOF
```

## 🧪 Testing & Verification

The project includes comprehensive smoke tests that verify:

### Infrastructure Tests
- AWS resource creation and configuration
- Network connectivity between nodes
- SSH access and hostname resolution

### Kubernetes Tests
- etcd cluster health
- Control plane component status
- Worker node registration
- Pod scheduling and execution
- Service discovery and networking
- Encryption at rest
- Data persistence

### Run Smoke Tests
```bash
make smoke-test
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Terraform Authentication Errors
```bash
# Check AWS credentials
aws sts get-caller-identity

# Reconfigure if needed
aws configure
```

#### 2. SSH Connection Failures
```bash
# Verify infrastructure is deployed
make status

# Check SSH key permissions
chmod 600 ~/.ssh/kubernetes-hard-way.pem

# Test connectivity
make verify-compute
```

#### 3. Kubernetes Components Not Starting
```bash
# Check service status on nodes
ssh root@server 'systemctl status kube-apiserver'
ssh root@server 'journalctl -u kube-apiserver -f'

# Verify certificates
ssh root@server 'ls -la /var/lib/kubernetes/'
```

#### 4. Pod Networking Issues
```bash
# Check routing tables
ssh root@server 'ip route'
ssh root@node-0 'ip route'
ssh root@node-1 'ip route'

# Recreate networking
make setup-networking
```

### Debug Mode
```bash
# Enable verbose output
export TF_LOG=DEBUG
make deploy

# Check specific components
make verify-compute
kubectl get nodes --kubeconfig admin.kubeconfig -v=6
```

## 🧹 Cleanup

### Partial Cleanup
```bash
# Destroy AWS infrastructure only
make destroy

# Clean Terraform state
make clean

# Clean jumpbox files
make cleanup-jumpbox
```

### Complete Cleanup
```bash
# Remove everything (recommended)
make full-cleanup
```

This will:
- Destroy all AWS resources
- Remove Terraform state files
- Clean up local SSH keys
- Remove Kubernetes certificates and configs
- Reset jumpbox environment

## 📁 Project Structure

```
kubernetes-hard-way-terraform/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Terraform variable definitions
├── outputs.tf              # Terraform output definitions
├── terraform.tfvars.example # Example configuration file
├── Makefile                # Automation scripts for deployment and management
├── modules/                # Terraform modules for organizing resources
│   ├── ec2/                # EC2 instance configuration
│   ├── keypair/            # SSH key pair management
│   ├── security-groups/    # Security group definitions
│   └── vpc/                # VPC and networking setup
├── scripts/                # Bash scripts for bootstrapping the cluster
│   ├── bootstrap-control-plane.sh
│   ├── bootstrap-etcd.sh
│   ├── bootstrap-workers.sh
│   ├── ...and more
└── README.md
```

## 🎓 Educational Value

This project maintains the educational goals of "Kubernetes the Hard Way":

### What You'll Learn
- **Kubernetes Architecture**: Deep understanding of control plane and worker components
- **PKI and TLS**: Certificate management and security in distributed systems
- **Container Runtime**: How containers are actually executed (containerd, runc)
- **Network Fundamentals**: Pod-to-pod communication, service discovery, and routing
- **etcd Operations**: Distributed consensus and data storage
- **AWS Infrastructure**: VPC design, security groups, and EC2 management
- **Infrastructure as Code**: Terraform best practices and module design

### What's Automated vs. Manual
- **Automated**: Infrastructure provisioning, file transfers, service configuration
- **Manual**: Understanding component relationships, debugging, and customization
- **Preserved**: All the learning about Kubernetes internals and troubleshooting

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines.

### How to Contribute
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Contribution Areas
- **Documentation improvements**
- **Additional cloud provider support (Azure, GCP)**
- **Enhanced monitoring and logging**
- **Alternative container runtimes**
- **Security enhancements**
- **Performance optimizations**

## 📖 References & Credits

- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) by Kelsey Hightower
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [etcd Documentation](https://etcd.io/docs/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Related Projects

- [kubernetes-the-hard-way](https://github.com/kelseyhightower/kubernetes-the-hard-way) - Original tutorial
- [kubernetes-the-hard-way-aws](https://github.com/prabhatsharma/kubernetes-the-hard-way-aws) - AWS-specific guide
- [terraform-aws-eks](https://github.com/terraform-aws-modules/terraform-aws-eks) - Production EKS clusters

## ⭐ Star History

If this project helped you learn Kubernetes, please give it a star! ⭐

---

**Happy Learning! 🚀**

*Remember: The goal is to understand Kubernetes, not just to get it running. Take time to explore the components and understand what each piece does.*