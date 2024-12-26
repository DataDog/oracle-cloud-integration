resource "oci_functions_function" "logs_function" {
  #Required
  application_id = var.function_app_ocid
  display_name   = local.function_name
  memory_in_mbs  = "256"

  #Optional
  defined_tags  = {}
  freeform_tags = var.freeform_tags
  image         = var.function_image_path
}
