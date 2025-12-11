output "private_key" {
  value       = tls_private_key.datadog_api_key.private_key_pem_pkcs8
  sensitive   = true
  description = "The private key in PKCS#8 PEM format (required by Datadog)"
}

output "public_key" {
  value       = tls_private_key.datadog_api_key.public_key_pem
  sensitive   = false
  description = "The public key in PEM format"
}

output "fingerprint" {
  value       = oci_identity_domains_api_key.datadog_key.fingerprint
  sensitive   = false
  description = "The fingerprint of the API key"
}

output "key_id" {
  value       = oci_identity_domains_api_key.datadog_key.id
  sensitive   = false
  description = "The OCID of the API key"
}
