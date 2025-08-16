# Security Group for Controller Node
resource "aws_security_group" "controller" {
  name_prefix = "${var.project_name}-controller-"
  vpc_id      = var.vpc_id

  description = "Security group for Kubernetes controller node"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Kubernetes API server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API server"
  }

  # etcd server client API
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.240.0.0/24"]
    description = "etcd server client API"
  }

  # Allow all internal communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.240.0.0/24"]
    description = "Internal cluster communication"
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["10.240.0.0/24"]
    description = "Internal cluster communication UDP"
  }

  # ICMP
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ICMP"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-controller-sg"
    Type = "controller"
  })
}

# Security Group for Worker Nodes
resource "aws_security_group" "worker" {
  name_prefix = "${var.project_name}-worker-"
  vpc_id      = var.vpc_id

  description = "Security group for Kubernetes worker nodes"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.240.0.0/24"]
    description = "kubelet API"
  }

  # NodePort Services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort Services"
  }

  # Allow all internal communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.240.0.0/24"]
    description = "Internal cluster communication"
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["10.240.0.0/24"]
    description = "Internal cluster communication UDP"
  }

  # ICMP
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ICMP"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-worker-sg"
    Type = "worker"
  })
}