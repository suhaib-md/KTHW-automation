output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

# For compatibility with existing code, return the same subnet ID for both private subnet slots
output "private_subnet_ids" {
  description = "IDs of the subnets (all using public subnet for simplicity)"
  value       = [aws_subnet.public.id, aws_subnet.public.id]
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}