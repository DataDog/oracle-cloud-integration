output "response" {
  value = jsondecode(data.external.find_resources.result["content"])
}
