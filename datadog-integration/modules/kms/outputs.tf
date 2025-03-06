output "api_key_secret_id" {
    description = "The secret OCID for the API key"
    value       = oci_vault_secret.api_key.id
}
