locals {
  tags = {
    ownedby = "datadog"
  }

  compartment_name = "Datadog"

  home_region_name = [
    for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]

  is_current_region_home_region = (var.region == local.home_region_name)
}

#Auth Variables
locals {
  user_name        = "dd-svc"
  user_group_name  = "${local.user_name}-admin"
  user_group_policy_name = "${local.user_name}-policy"
  dg_sch_name      = "dd-dynamic-group-connectorhubs"
  dg_fn_name       = "dd-dynamic-group-functions"
  dg_policy_name   = "dd-dynamic-group-policy"
}

locals {
  validation_error = data.external.pre_checks.result["error"]
  fail = data.external.pre_checks.result["status"] == "error" ? file("${local.validation_error}") : ""
}

# Variables for regions
locals {
  subscribed_regions = [for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions : region]
  subscribed_regions_list = [for region in local.subscribed_regions : region.region_name]

  # All supported regions list based on docker image existence
  supported_regions      = data.external.supported_regions
  supported_regions_list = [for entry in data.external.supported_regions : entry.result.value if entry.result.failure == ""]

  # Region object mapped to a region name
  subscribed_regions_map = tomap({
    for region in local.subscribed_regions :
    region.region_name => region
  })



  subscribed_regions_set = toset(local.subscribed_regions_list)
}
