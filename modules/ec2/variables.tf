variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_id" {
  description = "ID of the public subnet"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets (kept for compatibility but not used)"
  type        = list(string)
}

variable "controller_sg_id" {
  description = "ID of the controller security group"
  type        = string
}

variable "worker_sg_id" {
  description = "ID of the worker security group"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "AWS Key Pair name"
  type        = string
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default     = {}
}