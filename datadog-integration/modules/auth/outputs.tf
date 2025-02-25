output "user_id" {
  value = oci_identity_user.dd_auth_user
}

output "private_key" {
  value     = tls_private_key.this.private_key_pem
  sensitive = true
}
