data "external" "ensure_file" {
    depends_on = [null_resource.fetch_logging_services]
    program = ["bash", "modules/logging/search_resources.sh", var.compartment_ocid, local.excluded_services]
}
