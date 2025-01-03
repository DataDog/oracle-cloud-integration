# Output the "list" of all subscribed regions.

output "vcn_network_details" {
  depends_on  = [module.vcn]
  description = "Output of the created network infra"
  value = var.create_vcn ? {
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
  value       = oci_functions_application.metrics_function_app.id
}

output "function_application_function" {
  description = "OCID of the Function"
  value       = oci_functions_function.metrics_function.id
}

output "compartment_map" {
  description = "Derived namespaces"
  value       = local.final_namespaces
}

output "namespace_error" {
  description = "Message in case of invalid namespace"
  value       = length(local.derived_namespaces) > 0 ? "" : "Could not obtain any namespaces or compartments for which metrics should be sent. Make sure that the provided compartments contain the resources for the supported metrics namespaces."
}

output "connector_hub" {
  description = "Connector hub created for forwarding the data to the function"
  value       = [for v in oci_sch_service_connector.metrics_service_connector : { name = v.display_name, ocid = v.id }]
}

output "containerregistry_details" {
  description = "Output of pushing image to container registry"
  value       = {
    repository_ocid = oci_artifacts_container_repository.function_repo.id
    repository_name = oci_artifacts_container_repository.function_repo.display_name
    function_image_path = "${local.docker_image_path}:latest"
  }
}
