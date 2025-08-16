variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "kubernetes-hard-way"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.240.0.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium" # 2 vCPUs, 4GB RAM (closest to 2GB requirement while being practical)
}

variable "key_name" {
  description = "AWS Key Pair name for EC2 instances"
  type        = string
  # You'll need to create this key pair in AWS Console or via CLI
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Project     = "kubernetes-hard-way"
    Environment = "learning"
    ManagedBy   = "terraform"
  }
}