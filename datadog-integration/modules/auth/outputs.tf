output "user_id" {
  value = oci_identity_user.dd_auth.id
}

output "private_key" {
  value     = tls_private_key.this.private_key_pem_pkcs8
  sensitive = true
}

output "public_key_fingerprint" {
  value     = oci_identity_api_key.this.fingerprint
  sensitive = true
}

