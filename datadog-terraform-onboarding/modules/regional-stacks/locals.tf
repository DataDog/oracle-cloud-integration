locals {
  registry_host      = lower("${var.region_key}.ocir.io/iddfxd5j9l2o")
  metrics_image_path = "${local.registry_host}/oci-datadog-forwarder/metrics:latest"
  logs_image_path    = "${local.registry_host}/oci-datadog-forwarder/logs:latest"
  token_base_path    = "https://${var.region_key}.ocir.io/20180419/docker/token?service=${var.region_key}.ocir.io&scope=repository:iddfxd5j9l2o/oci-datadog-forwarder"
  token_logs         = "${local.token_base_path}/logs:pull"
  token_metrics      = "${local.token_base_path}/metrics:pull"
  image_base_path    = "https://${var.region_key}.ocir.io/v2/iddfxd5j9l2o/oci-datadog-forwarder"
  image_url_logs     = "${local.image_base_path}/logs/manifests/latest"
  image_url_metrics  = "${local.image_base_path}/metrics/manifests/latest"

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

  # Subnet region validation when OCID is provided (handles both 3-letter codes and full names)
  subnet_region_from_ocid = var.subnet_ocid != "" ? split(".", var.subnet_ocid)[3] : ""
  
  # Check if the region from OCID matches current region (either by full name or region key)
  # Convert extracted region to uppercase for comparison since region_key is uppercase
  subnet_region_matches = var.subnet_ocid == "" || (
    local.subnet_region_from_ocid == var.region || 
    upper(local.subnet_region_from_ocid) == var.region_key
  )
  
  # Simple subnet selection logic: use provided OCID or create new
  subnet_id = var.subnet_ocid != "" ? var.subnet_ocid : module.vcn[0].subnet_id[local.subnet]
}
