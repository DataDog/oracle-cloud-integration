output "connectorhub_details" {
  description = "Output of connector hub"
  value       = {
    service_connector_name = oci_sch_service_connector.service_log_connector.display_name
    service_connector_ocid = oci_sch_service_connector.service_log_connector.id
    audit_connector_name   = length(oci_sch_service_connector.audit_log_connector) > 0 ? oci_sch_service_connector.audit_log_connector[0].display_name : ""
    audit_connector_ocid   = length(oci_sch_service_connector.audit_log_connector) > 0 ? oci_sch_service_connector.audit_log_connector[0].id : ""
  }
}
