resource "oci_functions_application" "dd_function_app" {
  compartment_id = var.compartment_id
  display_name   = "dd-function-app"
  freeform_tags  = var.tags
  shape          = "GENERIC_X86_ARM"
  subnet_ids     = [
    var.subnet_id,
  ]
  config         = local.config
}

resource "oci_functions_function" "logs_function" {
  count           = var.logs_image_tag != "" ? 1 : 0
  application_id  = oci_functions_application.dd_function_app.id
  display_name    = "dd-logs-forwarder"
  memory_in_mbs   = "256"
  freeform_tags   = var.tags
  image           = local.logs_image_path
}

resource "oci_functions_function" "metrics_function" {
  count           = var.metrics_image_tag != "" ? 1 : 0
  application_id  = oci_functions_application.dd_function_app.id
  display_name    = "dd-metrics-forwarder"
  memory_in_mbs   = "256"
  freeform_tags   = var.tags
  image           = local.metrics_image_path
}
