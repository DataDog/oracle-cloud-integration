# Service Log Connector
resource "oci_sch_service_connector" "service_log_connector" {
    compartment_id = var.compartment_ocid
    display_name   = local.service_connector_name
    description    = "Terraform created connector hub to distribute service logs"

    source {
        kind = "logging"
        dynamic "log_sources" {
            for_each = var.service_log_groups
            content {
                compartment_id = log_sources.value.compartment_id
                log_group_id   = log_sources.value.log_group_id
            }
        }
    }

    target {
        kind              = "functions"
        batch_size_in_kbs = 5000
        batch_time_in_sec = 60
        function_id       = var.function_ocid
    }

    freeform_tags = var.freeform_tags
}

# Audit Log Connector
resource "oci_sch_service_connector" "audit_log_connector" {
    count          = length(var.audit_log_compartments) > 0 ? 1 : 0
    compartment_id = var.compartment_ocid
    display_name   = local.audit_connector_name
    description    = "Terraform created connector hub to distribute audit logs"

    source {
        kind = "logging"
        dynamic "log_sources" {
            for_each = var.audit_log_compartments
            content {
                compartment_id = log_sources.value
                log_group_id   = "_Audit"
            }
        }
    }

    target {
        kind              = "functions"
        batch_size_in_kbs = 5000
        batch_time_in_sec = 60
        function_id       = var.function_ocid
    }

    freeform_tags = var.freeform_tags
}
