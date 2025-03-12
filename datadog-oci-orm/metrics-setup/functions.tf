resource "oci_functions_application" "metrics_function_app" {
  depends_on     = [data.oci_core_subnet.input_subnet]
  count          = local.is_service_user_available ? 1 : 0
  compartment_id = var.compartment_ocid
  config = {
    "DD_API_KEY"               = var.datadog_api_key
    "DD_COMPRESS"              = "true"
    "DD_INTAKE_HOST"           = var.datadog_environment
    "DD_INTAKE_LOGS"           = "false"
    "DD_MAX_POOL"              = "20"
    "DETAILED_LOGGING_ENABLED" = "false"
    "TENANCY_OCID"             = var.tenancy_ocid
  }
  defined_tags  = {}
  display_name  = local.oci_function_app
  freeform_tags = local.freeform_tags
  network_security_group_ids = [
  ]
  shape = var.function_app_shape
  subnet_ids = [
    data.oci_core_subnet.input_subnet[0].id,
  ]
}

resource "oci_functions_function" "metrics_function" {
  depends_on = [oci_functions_application.metrics_function_app, null_resource.wait_for_image]
  count      = local.is_service_user_available ? 1 : 0
  #Required
  application_id = oci_functions_application.metrics_function_app[0].id
  display_name   = local.oci_function_name
  memory_in_mbs  = "256"

  #Optional
  defined_tags  = {}
  freeform_tags = local.freeform_tags
  image         = local.docker_image_path
}
