# SSH Key Information
output "ssh_key_info" {
  description = "SSH key pair information"
  value = {
    key_name         = module.keypair.key_name
    private_key_path = module.keypair.private_key_path
    public_key_path  = module.keypair.public_key_path
    fingerprint      = module.keypair.fingerprint
  }
}

# Controller Node Outputs
output "controller_public_ip" {
  description = "Public IP of the controller node"
  value       = module.ec2_instances.controller_public_ip
}

output "controller_private_ip" {
  description = "Private IP of the controller node"
  value       = module.ec2_instances.controller_private_ip
}

output "controller_instance_id" {
  description = "Instance ID of the controller node"
  value       = module.ec2_instances.controller_instance_id
}

# Worker Nodes Outputs
output "worker_nodes" {
  description = "Worker nodes information"
  value = {
    node-0 = {
      public_ip   = module.ec2_instances.worker_public_ips[0]
      private_ip  = module.ec2_instances.worker_private_ips[0]
      instance_id = module.ec2_instances.worker_instance_ids[0]
    }
    node-1 = {
      public_ip   = module.ec2_instances.worker_public_ips[1]
      private_ip  = module.ec2_instances.worker_private_ips[1]
      instance_id = module.ec2_instances.worker_instance_ids[1]
    }
  }
}

# Network Information
output "vpc_info" {
  description = "VPC information"
  value = {
    vpc_id           = module.vpc.vpc_id
    vpc_cidr         = module.vpc.vpc_cidr_block
    public_subnet_id = module.vpc.public_subnet_id
    private_subnet_ids = module.vpc.private_subnet_ids
  }
}

# Security Group Information
output "security_groups" {
  description = "Security group information"
  value = {
    controller_sg_id = module.security_groups.controller_sg_id
    worker_sg_id     = module.security_groups.worker_sg_id
  }
}

# SSH Connection Information
output "ssh_commands" {
  description = "SSH connection commands"
  value = {
    controller = "ssh -i ${module.keypair.private_key_path} admin@${module.ec2_instances.controller_public_ip}"
    worker_0   = "ssh -i ${module.keypair.private_key_path} admin@${module.ec2_instances.worker_public_ips[0]}"
    worker_1   = "ssh -i ${module.keypair.private_key_path} admin@${module.ec2_instances.worker_public_ips[1]}"
  }
}
