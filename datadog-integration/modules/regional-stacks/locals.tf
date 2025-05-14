locals {
  registry_host      = lower("${var.region_key}.ocir.io/iduhc9hzgn3o")
  metrics_image_path = "${local.registry_host}/oci-datadog-forwarder/metrics:latest"
  logs_image_path    = "${local.registry_host}/oci-datadog-forwarder/logs:latest"

  config = {
    "DD_SITE"                  = var.datadog_site,
    "HOME_REGION"              = var.home_region,
    "API_KEY_SECRET_OCID"      = var.api_key_secret_id
    "DATADOG_TAGS"             = "",
    "EXCLUDE"                  = "{}",
    "DD_BATCH_SIZE"            = "1000",
    "TENANCY_OCID"             = var.tenancy_ocid,
    "DETAILED_LOGGING_ENABLED" = "false"
  }
}

locals {
  # Names for the network infra
  vcn_name        = "dd-vcn"
  nat_gateway     = "${local.vcn_name}-natgateway"
  service_gateway = "${local.vcn_name}-servicegateway"
  subnet          = "${local.vcn_name}-private-subnet"
}
