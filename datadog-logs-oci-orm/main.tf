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

module "functionapp" {
    source = "./modules/functionapp"
    compartment_ocid = var.compartment_ocid
    freeform_tags = local.freeform_tags
    resource_name_prefix = var.resource_name_prefix
    function_app_shape = var.function_app_shape
    subnet_ocid = module.vcn.vcn_network_details.subnet_id
    datadog_api_key = var.datadog_api_key
    datadog_endpoint = var.datadog_endpoint
    datadog_tags = var.datadog_tags
}
