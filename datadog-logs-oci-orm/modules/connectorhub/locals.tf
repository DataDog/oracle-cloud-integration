locals {
  # Names for the service connector
  service_connector_name = "${var.resource_name_prefix}-service-logs-connector"
  audit_connector_name = "${var.resource_name_prefix}-audit-logs-connector"
}
