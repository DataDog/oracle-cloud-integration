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
