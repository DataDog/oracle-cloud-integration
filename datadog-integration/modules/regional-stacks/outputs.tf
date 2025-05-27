output "output_ids" {
  value = {
    subnet       = var.subnet_partial_name != "" ? data.oci_core_subnets.existing_subnet[0].subnets[0].id : module.vcn[0].subnet_id[local.subnet]
    function_app = oci_functions_application.dd_function_app.id
  }
}
