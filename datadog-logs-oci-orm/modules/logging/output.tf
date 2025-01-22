output "details" {
  description = "Output of logging"
  value       = {
    logs = local.logs_map
    resources_without_logs = local.resources_without_logs
    log_groups = local.loggroup_ids
    }
}
