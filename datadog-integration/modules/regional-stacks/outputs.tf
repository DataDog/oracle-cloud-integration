output "output_ids" {
  value = {
    subnet       = local.subnet_id
    function_app = local.function_app_id
  }
}
