data "external" "find_resources" {
    program = ["bash", "modules/resourcediscovery/search_resources.sh", var.compartment_ocid, var.group_id, local.resource_types_string]
}
