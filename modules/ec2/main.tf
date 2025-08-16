# Data source for Debian 12 AMI
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian official

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Cloud-init script for basic setup
locals {
  cloud_init_script = base64encode(file("${path.module}/cloud-init.yml"))
}

# Controller Node (server)
resource "aws_instance" "controller" {
  ami                     = data.aws_ami.debian.id
  instance_type           = var.instance_type
  key_name                = var.key_name
  vpc_security_group_ids  = [var.controller_sg_id]
  subnet_id               = var.public_subnet_id
  private_ip              = "10.240.0.10"
  
  # Storage
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    
    tags = merge(var.tags, {
      Name = "${var.project_name}-controller-root"
    })
  }

  # Cloud-init for initial setup
  user_data = local.cloud_init_script

  # Instance metadata options
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, {
    Name = "server"
    Role = "controller"
    Type = "kubernetes-controller"
  })
}

# Worker Nodes
resource "aws_instance" "workers" {
  count = 2

  ami                     = data.aws_ami.debian.id
  instance_type           = var.instance_type
  key_name                = var.key_name
  vpc_security_group_ids  = [var.worker_sg_id]
  subnet_id               = var.private_subnet_ids[count.index]
  private_ip              = "10.240.0.${20 + count.index}"
  
  # Storage
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    
    tags = merge(var.tags, {
      Name = "${var.project_name}-worker-${count.index}-root"
    })
  }

  # Cloud-init for initial setup
  user_data = local.cloud_init_script

  # Instance metadata options
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, {
    Name = "node-${count.index}"
    Role = "worker"
    Type = "kubernetes-worker"
  })
}