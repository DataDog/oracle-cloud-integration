data "oci_logging_log_groups" "datadog_log_group" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
    display_name = "datadog-service-logs"
}

data "oci_logging_log_groups" "audit_log_group" {
    count = var.enable_audit_log_forwarding ? 1 : 0

    #Required
    compartment_id = var.compartment_ocid

    #Optional
    display_name = "_Audit"
}
