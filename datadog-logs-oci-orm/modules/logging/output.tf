output "details" {
  description = "Output of logging"
  value       = {
    preexisting_loggroups = local.log_groups
    datadog_service_loggroup_id = length(oci_logging_log_group.datadog_service_log_group) > 0 ? oci_logging_log_group.datadog_service_log_group[0].id : null
    loggroups = { for k, v in data.external.logs_outside_compartment : k => v.result.content if v.result.content != "" }
  }
}
