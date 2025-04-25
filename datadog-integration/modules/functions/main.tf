terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

resource "oci_functions_application" "dd_function_app" {
  compartment_id = var.compartment_id
  display_name   = "dd-function-app"
  freeform_tags  = var.tags
  shape          = "GENERIC_X86_ARM"
  subnet_ids = [
    var.subnet_id,
  ]
  config = local.config
}

resource "oci_functions_function" "logs_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-logs-forwarder"
  memory_in_mbs  = "1024"
  freeform_tags  = var.tags
  image          = local.logs_image_path
}

resource "oci_functions_function" "metrics_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-metrics-forwarder"
  memory_in_mbs  = "512"
  freeform_tags  = var.tags
  image          = local.metrics_image_path
}
