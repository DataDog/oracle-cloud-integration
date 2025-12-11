output "output_ids" {
  value = {
    subnet       = local.subnet_id
    function_app = oci_functions_application.dd_function_app.id
  }
}
