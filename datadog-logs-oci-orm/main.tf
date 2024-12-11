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

module "containerregistry" {
    source = "./modules/containerregistry"
    oci_region_key = local.oci_region_key
    tenancy_ocid = var.tenancy_ocid
    user_ocid = var.service_user_ocid == "" ? var.current_user_ocid : var.service_user_ocid
    auth_token_description = var.auth_token_description
    auth_token = var.auth_token
    count = var.function_image_path == "" ? 1 : 0
}
