module "vcn" {
    source = "./modules/vcn"
    compartment_ocid = var.compartment_ocid
    freeform_tags = local.freeform_tags
    resource_name_prefix = var.resource_name_prefix
    create_vcn = var.create_vcn
    subnet_ocid = var.subnet_ocid
}
