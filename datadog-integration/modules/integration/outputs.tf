output "api_output" {
  value = {
    response = restapi_object.datadog_tenancy_integration.api_response
  }
}

output "stack_id_from_job" {
  value = data.external.stack_info.result
}
