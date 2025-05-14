output "output_ids" {
  value = {
    subnet       = module.vcn.subnet_id[local.subnet]
    function_app = oci_functions_application.dd_function_app.id
  }
}
