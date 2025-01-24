data "oci_logging_log_groups" "datadog_log_group" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
    display_name = "datadog-service-logs"
}
