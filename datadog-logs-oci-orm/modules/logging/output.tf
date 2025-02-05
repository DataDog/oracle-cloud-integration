output "details" {
  description = "Output of logging module execution"
  value       = {
    preexisting_log_groups = local.log_groups
    datadog_service_log_group_id = length(oci_logging_log_group.datadog_service_log_group) > 0 ? oci_logging_log_group.datadog_service_log_group[0].id : null
  }
}
