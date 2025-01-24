data "oci_logging_log_groups" "test_log_groups" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
    display_name = "datadog-service-logs"
}
