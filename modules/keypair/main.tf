# Generate RSA private key
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS key pair using the generated public key
resource "aws_key_pair" "main" {
  key_name   = var.key_name
  public_key = tls_private_key.main.public_key_openssh

  tags = merge(var.tags, {
    Name = "${var.project_name}-keypair"
  })
}

# Save private key to local file
resource "local_file" "private_key" {
  content         = tls_private_key.main.private_key_pem
  filename        = pathexpand("~/.ssh/${var.key_name}.pem")
  file_permission = "0400"
}

# Save public key to local file
resource "local_file" "public_key" {
  content         = tls_private_key.main.public_key_openssh
  filename        = pathexpand("~/.ssh/${var.key_name}.pub")
  file_permission = "0644"
}