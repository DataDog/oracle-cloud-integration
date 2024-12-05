output "function_app_details" {
  description = "Output of creating function application"
  value       = {
    function_app_ocid = oci_functions_application.logs_function_app.id
    function_app_name = oci_functions_application.logs_function_app.display_name
  }
}
