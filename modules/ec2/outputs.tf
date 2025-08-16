output "controller_public_ip" {
  description = "Public IP of the controller node"
  value       = aws_instance.controller.public_ip
}

output "controller_private_ip" {
  description = "Private IP of the controller node"
  value       = aws_instance.controller.private_ip
}

output "controller_instance_id" {
  description = "Instance ID of the controller node"
  value       = aws_instance.controller.id
}

output "worker_public_ips" {
  description = "Public IPs of the worker nodes"
  value       = aws_instance.workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IPs of the worker nodes"
  value       = aws_instance.workers[*].private_ip
}

output "worker_instance_ids" {
  description = "Instance IDs of the worker nodes"
  value       = aws_instance.workers[*].id
}