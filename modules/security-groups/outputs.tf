output "controller_sg_id" {
  description = "ID of the controller security group"
  value       = aws_security_group.controller.id
}

output "worker_sg_id" {
  description = "ID of the worker security group"
  value       = aws_security_group.worker.id
}