output "private_key" {
  value       = data.local_sensitive_file.private_key.content
  sensitive   = true
  description = "The private key"
} 