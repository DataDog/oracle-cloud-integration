/*
module "vcn" {
    source = "./modules/vcn"
    compartment_ocid = var.vcn_compartment
    freeform_tags = local.freeform_tags
    resource_name_prefix = var.resource_name_prefix
    create_vcn = var.create_vcn
    subnet_ocid = var.subnet_ocid
}

module "policy" {
    source = "./modules/policy"
    tenancy_ocid = var.tenancy_ocid
    resource_name_prefix = var.resource_name_prefix
    freeform_tags = local.freeform_tags
}
*/

module "logging" {
  for_each = { for target in local.logging_targets : "${target.compartment_id}_${target.service_id}" => target }
  source = "./modules/logging"
  compartment_ocid = each.value.compartment_id
  service_id       = each.value.service_id
  resource_types   = each.value.resource_types
}

resource "null_resource" "cleanup_files" {
  depends_on = [module.logging]
  provisioner "local-exec" {
    command = "rm -f oci_*.json"
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}
