output "idcs_endpoint" {
  description = "The IDCS endpoint for the domain"
  value       = data.oci_identity_domain.domain.url
}

output "is_default_domain" {
  description = "Whether this is the default domain for the tenancy"
  value       = var.domain_name == "Default"
} 