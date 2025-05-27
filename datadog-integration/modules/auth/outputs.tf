output "user_id" {
  value = var.existing_user_id != null ? var.existing_user_id : oci_identity_domains_user.dd_auth[0].id
}

output "group_id" {
  value = var.existing_group_id != null ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].id
}

output "domain_id" {
  value = data.oci_identity_domain.selected_domain.id
}

output "service_connector_dynamic_group_id" {
  description = "The OCID of the service connector dynamic group"
  value       = oci_identity_domains_dynamic_resource_group.service_connector.id
}

output "forwarding_function_dynamic_group_id" {
  description = "The OCID of the forwarding function dynamic group"
  value       = oci_identity_domains_dynamic_resource_group.forwarding_function.id
}
