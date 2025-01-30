resource "oci_logging_log_group" "datadog_service_log_group" {
    count = length(local.resources_without_logs) > 0 ? 1 : 0
    #Required
    compartment_id = var.compartment_ocid
    display_name = "datadog-service-logs"

    #Optional
    description = "[DO NOT REMOVE] This log group is managed by the system. Do not edit. It is used for forwarding logs to Datadog."
    freeform_tags = var.freeform_tags
}

resource "oci_logging_log" "service_logs" {
    for_each = local.resources_without_logs
    #Required
    display_name = each.key
    log_group_id = oci_logging_log_group.datadog_service_log_group[0].id
    log_type = "SERVICE"

    #Optional
    configuration {
        #Required
        source {
            #Required
            category = each.value.category
            resource = each.value.service_id == "objectstorage" ? each.value.resource_name : each.value.resource_id
            service = each.value.service_id
            source_type = "OCISERVICE"

        }

        #Optional
        compartment_id = var.compartment_ocid
    }
    freeform_tags = var.freeform_tags
}
