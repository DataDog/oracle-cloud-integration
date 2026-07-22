data "http" "token_logs" {
  url = local.token_logs
}

data "http" "token_metrics" {
  url = local.token_metrics
}

locals {
  logs_token        = jsondecode(data.http.token_logs.response_body).token
  metrics_token     = jsondecode(data.http.token_metrics.response_body).token
  image_sha_logs    = contains(keys(data.http.logs_image.response_headers), "Docker-Content-Digest") ? data.http.logs_image.response_headers["Docker-Content-Digest"] : (contains(keys(data.http.logs_image.response_headers), "docker-content-digest") ? data.http.logs_image.response_headers["docker-content-digest"] : "")
  image_sha_metrics = contains(keys(data.http.metrics_image.response_headers), "Docker-Content-Digest") ? data.http.metrics_image.response_headers["Docker-Content-Digest"] : (contains(keys(data.http.metrics_image.response_headers), "docker-content-digest") ? data.http.metrics_image.response_headers["docker-content-digest"] : "")
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

# Validate that the provided subnet OCID exists and is accessible
data "oci_core_subnet" "provided_subnet" {
  count     = var.subnet_ocid != "" ? 1 : 0
  subnet_id = var.subnet_ocid
}

data "oci_core_vcn" "dd_vcn" {
  count  = var.subnet_ocid == "" ? 1 : 0
  vcn_id = module.vcn[0].vcn_id
}

# Check if this region's own vault already exists in state. This module is
# deployed as its own root module per region, so `terraform state list` here
# only ever contains this region's resources. Used to make create_regional_vault
# sticky: once created, the regional vault must not be destroyed just because
# live quota later drops to 0 (the vault itself consumes a quota unit).
data "external" "check_regional_vault_in_state" {
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -q "oci_kms_vault\.datadog_vault" && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}
