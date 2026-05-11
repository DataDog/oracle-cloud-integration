locals {
  defined_tags_map   = jsondecode(var.defined_tags)
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

  # ID of an existing dd-function-app, frozen at first apply via terraform_data.
  # Using terraform_data rather than the data source directly avoids the idempotency
  # trap: without this freeze, the data source finds the app Terraform itself just
  # created, flips count to 0, and plans to destroy the managed app on the next apply.
  #
  # When var.subnet_ocid is explicitly provided we treat this as a fresh deploy and
  # do NOT adopt the orphaned app, so the explicit subnet preference is honoured.
  existing_function_app_id = var.subnet_ocid == "" ? try(tostring(terraform_data.adopted_function_app_id.output), null) : null

  # The application ID to attach Datadog functions to.
  # Prefers the orphaned app so the customer's custom function stays co-located with
  # the Datadog forwarders.
  function_app_id = coalesce(
    local.existing_function_app_id,
    one(oci_functions_application.dd_function_app[*].id)
  )

  # Only provision VCN/subnet when there is no existing app to inherit the network from
  # and no explicit subnet OCID was provided.
  create_network = local.existing_function_app_id == null && var.subnet_ocid == ""

  # Subnet selection priority: explicit OCID → existing app's subnet → newly created subnet
  subnet_id = (
    var.subnet_ocid != "" ? var.subnet_ocid :
    local.existing_function_app_id != null && length(data.oci_functions_applications.existing_dd_function_app.applications) > 0 ?
      data.oci_functions_applications.existing_dd_function_app.applications[0].subnet_ids[0] :
    module.subnet[0].subnet_id[local.subnet]
  )
}
