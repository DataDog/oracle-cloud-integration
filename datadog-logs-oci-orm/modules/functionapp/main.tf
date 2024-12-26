resource "oci_functions_application" "logs_function_app" {
  compartment_id = var.compartment_ocid
  config = {
    "DATADOG_HOST"  = var.datadog_endpoint
    "DATADOG_TOKEN" = var.datadog_api_key
    "DD_COMPRESS"   = "true"
    "DATADOG_TAGS"  = var.datadog_tags
  }
  defined_tags  = {}
  display_name  = "${local.function_app_name}"
  freeform_tags = var.freeform_tags
  network_security_group_ids = [
  ]
  shape = var.function_app_shape
  subnet_ids = [
    var.subnet_ocid,
  ]
}
