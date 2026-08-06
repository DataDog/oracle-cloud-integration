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

  # The region/secret actually backing this function's Datadog API key: this
  # region's own vault when local.create_regional_vault is true (the caller has
  # already checked vault quota in this region), otherwise the home-region vault.
  vault_region      = local.create_regional_vault ? var.region : var.home_region
  api_key_secret_id = local.create_regional_vault ? oci_vault_secret.api_key[0].id : var.api_key_secret_id

  # var.create_regional_vault reflects a LIVE read of tenancy-wide vault quota
  # in this region (computed by the caller), re-evaluated on every apply. Once
  # this region's vault actually exists, it itself consumes one unit of that
  # same quota, so a later apply can see available == 0 and want to flip
  # var.create_regional_vault back to false -- which would destroy the vault,
  # key and secret this module just created. Make the decision sticky: once
  # the vault is in state for this region (checked by the caller and passed
  # in as var.regional_vault_exists_in_state -- this state check must live in
  # the root module, not here, for the same module-level depends_on reason
  # documented in vault_quota.tf), keep creating it regardless of what the
  # live quota check says on subsequent applies.
  create_regional_vault = var.region != var.home_region && (
    var.create_regional_vault ||
    var.regional_vault_exists_in_state == "true"
  )
}

locals {
  config = {
    "DD_SITE"                  = var.datadog_site,
    "HOME_REGION"              = local.vault_region,
    "API_KEY_SECRET_OCID"      = local.api_key_secret_id
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

  # Simple subnet selection logic: use provided OCID or create new (subnet from our subnet submodule when we create VCN)
  subnet_id = var.subnet_ocid != "" ? var.subnet_ocid : module.subnet[0].subnet_id[local.subnet]
}
