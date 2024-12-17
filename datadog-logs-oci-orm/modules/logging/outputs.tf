output "response" {
  value = jsondecode(data.external.ensure_file.result["content"])
}
