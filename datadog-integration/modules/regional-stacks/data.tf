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
