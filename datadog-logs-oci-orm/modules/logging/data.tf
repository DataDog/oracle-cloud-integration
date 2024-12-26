data "external" "find_resources" {
    program = ["bash", "modules/logging/search_resources.sh", var.compartment_ocid, var.service_id, local.resource_type_names]
}
