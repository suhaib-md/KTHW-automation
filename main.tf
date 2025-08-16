terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Key Pair Module - Create SSH key pair automatically
module "keypair" {
  source = "./modules/keypair"
  
  project_name = var.project_name
  key_name     = var.key_name
  
  tags = var.common_tags
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  
  tags = var.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security-groups"
  
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  
  tags = var.common_tags
}

# EC2 Instances Module
module "ec2_instances" {
  source = "./modules/ec2"
  
  project_name           = var.project_name
  vpc_id                 = module.vpc.vpc_id
  public_subnet_id       = module.vpc.public_subnet_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  controller_sg_id       = module.security_groups.controller_sg_id
  worker_sg_id           = module.security_groups.worker_sg_id
  instance_type          = var.instance_type
  key_name               = module.keypair.key_name
  
  tags = var.common_tags
  
  # Ensure key pair is created before EC2 instances
  depends_on = [module.keypair]
}