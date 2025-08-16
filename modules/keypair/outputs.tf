output "key_name" {
  description = "Name of the created key pair"
  value       = aws_key_pair.main.key_name
}

output "key_pair_id" {
  description = "ID of the created key pair"
  value       = aws_key_pair.main.key_pair_id
}

output "fingerprint" {
  description = "Fingerprint of the key pair"
  value       = aws_key_pair.main.fingerprint
}

output "private_key_path" {
  description = "Path to the private key file"
  value       = local_file.private_key.filename
}

output "public_key_path" {
  description = "Path to the public key file"
  value       = local_file.public_key.filename
}