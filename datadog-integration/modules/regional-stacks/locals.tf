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

  # Subnet search logic - compartments to search
  subnet_search_compartments = var.subnet_partial_name != "" ? merge(
    # Include the root tenancy as a compartment to search
    {
      (var.tenancy_ocid) = {
        id   = var.tenancy_ocid
        name = "tenancy-root"
      }
    },
    # Add all other compartments
    length(data.oci_identity_compartments.all_compartments) > 0 ? {
      for comp in data.oci_identity_compartments.all_compartments[0].compartments :
      comp.id => {
        id   = comp.id
        name = comp.name
      }
    } : {}
  ) : {}

  # Collect all found subnets from all compartments
  all_found_subnets = var.subnet_partial_name != "" ? flatten([
    for compartment_id, subnet_data in data.oci_core_subnets.subnets_by_compartment : [
      for subnet in subnet_data.subnets : {
        id                   = subnet.id
        display_name         = subnet.display_name
        compartment_id       = subnet.compartment_id
        vcn_id               = subnet.vcn_id
        cidr_block           = subnet.cidr_block
        found_in_compartment = local.subnet_search_compartments[compartment_id].name
      }
    ]
  ]) : []

  # Get the first found subnet (if any)
  found_subnet_id = length(local.all_found_subnets) > 0 ? local.all_found_subnets[0].id : null

  # Subnet selection logic - use existing subnet if found, otherwise use created VCN subnet
  subnet_id = local.found_subnet_id != null ? local.found_subnet_id : module.vcn[0].subnet_id[local.subnet]
}
