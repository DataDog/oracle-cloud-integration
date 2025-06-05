data "http" "token_logs" {
  url = local.token_logs
}

data "http" "token_metrics" {
  url = local.token_metrics
}

locals {
  logs_token        = jsondecode(data.http.token_logs.response_body).token
  metrics_token     = jsondecode(data.http.token_metrics.response_body).token
  image_sha_logs    = data.http.logs_image.response_headers.Docker-Content-Digest
  image_sha_metrics = data.http.metrics_image.response_headers.Docker-Content-Digest
}


data "http" "logs_image" {
  url = local.image_url_logs
  request_headers = {
    Accept        = "application/vnd.oci.image.index.v1+json"
    Authorization = "Bearer ${local.logs_token}"
  }
}

data "http" "metrics_image" {
  url = local.image_url_metrics
  request_headers = {
    Accept        = "application/vnd.oci.image.index.v1+json"
    Authorization = "Bearer ${local.metrics_token}"
  }
}
# Subnet finder logic - inline to avoid OCI RM subdirectory issues
# Get all compartments in the tenancy (including nested ones)
data "oci_identity_compartments" "all_compartments" {
  count                     = var.subnet_partial_name != "" ? 1 : 0
  compartment_id            = var.tenancy_ocid
  compartment_id_in_subtree = true
  access_level              = "ACCESSIBLE"
  state                     = "ACTIVE"
}

# Search for subnets in each compartment
data "oci_core_subnets" "subnets_by_compartment" {
  for_each = var.subnet_partial_name != "" ? local.subnet_search_compartments : {}

  compartment_id = each.value.id

  filter {
    name   = "display_name"
    values = [".*${var.subnet_partial_name}.*"]
    regex  = true
  }
} 