# Output the "list" of all subscribed regions.

output "vcn_network_details" {
  depends_on  = [module.vcn]
  description = "Output of the created network infra"
  value = var.create_vcn && length(module.vcn) > 0 ? {
    vcn_id             = module.vcn[0].vcn_id
    nat_gateway_id     = module.vcn[0].nat_gateway_id
    nat_route_id       = module.vcn[0].nat_route_id
    service_gateway_id = module.vcn[0].service_gateway_id
    sgw_route_id       = module.vcn[0].sgw_route_id
    subnet_id          = module.vcn[0].subnet_id[local.subnet]
    } : {
    vcn_id             = ""
    nat_gateway_id     = ""
    nat_route_id       = ""
    service_gateway_id = ""
    sgw_route_id       = ""
    subnet_id          = var.function_subnet_id
  }
}

output "function_application" {
  description = "OCID of the Function app"
  value       = [for app in oci_functions_application.metrics_function_app : app.id]
}

output "function_application_function" {
  description = "OCID of the Function"
  value       = [for app in oci_functions_function.metrics_function : app.id]
}

output "compartment_map" {
  description = "Derived namespaces"
  value       = local.final_namespaces
}

output "service_account_error" {
  description = "Message in case service user has not been created."
  value       = local.is_service_user_available ? "" : "Service user not available to create function images. Please run the policy stack to create the service user."
}

output "namespace_error" {
  description = "Message in case of invalid namespace"
  value       = length(local.derived_namespaces) > 0 ? "" : "Could not obtain any namespaces or compartments for which metrics should be sent. Make sure that the provided compartments contain the resources for the supported metrics namespaces."
}

output "connector_hub" {
  description = "Connector hub created for forwarding the data to the function"
  value       = [for v in oci_sch_service_connector.metrics_service_connector : { name = v.display_name, ocid = v.id }]
}
