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
    freeform_tags = local.freeform_tags
}

module "functionapp" {
    source = "./modules/functionapp"
    compartment_ocid = var.compartment_ocid
    freeform_tags = local.freeform_tags
    resource_name_prefix = var.resource_name_prefix
    subnet_ocid = module.vcn.vcn_network_details.subnet_id
    datadog_api_key = var.datadog_api_key
    datadog_endpoint = var.datadog_endpoint
    datadog_tags = var.datadog_tags
}

module "containerregistry" {
    source = "./modules/containerregistry"
    region = var.region
    tenancy_ocid = var.tenancy_ocid
    username = var.oci_docker_username
    auth_token = var.oci_docker_password
    resource_name_prefix = var.resource_name_prefix
    compartment_ocid = var.compartment_ocid
    freeform_tags = local.freeform_tags
}

module "function" {
    depends_on = [module.containerregistry]
    source = "./modules/function"
    freeform_tags = local.freeform_tags
    function_app_name = module.functionapp.function_app_details.function_app_name
    function_app_ocid = module.functionapp.function_app_details.function_app_ocid
    function_image_path = module.containerregistry.containerregistry_details.function_image_path
}

module "resourcediscovery" {
    for_each = { for target in local.logging_targets : "${target.compartment_id}_${target.service_id}" => target }
    source = "./modules/resourcediscovery"
    compartment_ocid = each.value.compartment_id
    group_id = each.value.service_id
    resource_types = [for rt in each.value.resource_types : rt.name]
}

module "logging" {
    for_each = local.logging_compartment_ids
    source = "./modules/logging"
    tenancy_ocid = var.tenancy_ocid
    compartment_ocid = each.value
    service_map = local.service_map
    resources = flatten(lookup(local.compartment_resources,each.value,[]))
}

module "connectorhub" {
    source = "./modules/connectorhub"
    freeform_tags = local.freeform_tags
    compartment_ocid = var.compartment_ocid
    resource_name_prefix = var.resource_name_prefix
    function_ocid = module.function.function_details.function_ocid
    service_log_groups = local.service_log_groups
    audit_log_compartments = var.enable_audit_log_forwarding ? local.logging_compartment_ids : []
}
