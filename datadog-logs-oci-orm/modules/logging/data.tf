data "oci_logging_log_groups" "log_groups" {
    #Required
    compartment_id = var.compartment_ocid
}

data "oci_logging_logs" "existing_logs" {
    #Required
    for_each = { for log_group in data.oci_logging_log_groups.log_groups.log_groups : log_group.id => log_group }
    log_group_id = each.value.id
}
