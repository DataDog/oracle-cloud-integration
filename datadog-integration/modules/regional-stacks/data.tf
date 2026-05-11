data "oci_functions_applications" "existing_dd_function_app" {
  compartment_id = var.compartment_ocid
  display_name   = "dd-function-app"
  state          = "ACTIVE"
}

check "adopted_app_config" {
  # When an orphaned dd-function-app is adopted, Terraform cannot update its config
  # (the resource is unmanaged). Warn if the key forwarding settings diverge from
  # the current stack variables so the operator knows to update them manually via
  # the OCI Console or CLI.
  assert {
    condition = (
      local.existing_function_app_id == null ||
      length(data.oci_functions_applications.existing_dd_function_app.applications) == 0 ||
      (
        lookup(data.oci_functions_applications.existing_dd_function_app.applications[0].config, "DD_SITE", "") == var.datadog_site &&
        lookup(data.oci_functions_applications.existing_dd_function_app.applications[0].config, "API_KEY_SECRET_OCID", "") == var.api_key_secret_id
      )
    )
    error_message = "Adopted dd-function-app config is stale: DD_SITE or API_KEY_SECRET_OCID differ from current stack variables. Update the application config manually via the OCI Console or with: oci fn application update --application-id ${coalesce(local.existing_function_app_id, "n/a")} --config '{...}'."
  }
}

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
  count  = local.create_network ? 1 : 0
  vcn_id = module.vcn[0].vcn_id
}
