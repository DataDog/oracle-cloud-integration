output "api_key_secret_id" {
  description = "The secret OCID for the API key (created on the create path, reused on the reuse path)"
  value       = local.reuse_vault ? local.existing_secret_id : oci_vault_secret.api_key[0].id
}

output "vault_id" {
  description = "The OCID of the datadog-vault (created or reused)"
  value       = local.vault_id
}

output "key_id" {
  description = "The OCID of the datadog-key (created or reused)"
  value       = local.key_id
}

output "reused_vault" {
  description = "True when an existing vault was reused instead of created"
  value       = local.reuse_vault
}
