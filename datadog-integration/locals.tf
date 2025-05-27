locals {
  tags = {
    ownedby = "datadog"
  }

  user_name        = "dd-svc"

  home_region_name = [
    for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]

  is_current_region_home_region = (var.region == local.home_region_name)

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
