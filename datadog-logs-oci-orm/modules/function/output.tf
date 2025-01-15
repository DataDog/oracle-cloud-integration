output "function_details" {
  description = "Output of function creation"
  value       = {
    function_ocid = oci_functions_function.logs_function.id
    function_name = oci_functions_function.logs_function.display_name
  }
}
