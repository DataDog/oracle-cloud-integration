locals {
  tags = {
    ownedby = "datadog"
  }

  compartment_name = "Datadog"
  user_name        = "dd-svc"

  home_region_name = [
    for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]

  # All subscribed regions list
  subscribed_regions_list = [for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions : region.region_name]

  # Region object mapped to a region name
  subscribed_regions_map = tomap({
    for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions :
    region.region_name => region
  })

  subscribed_regions_set = toset(local.subscribed_regions_list)

  is_current_region_home_region = (var.region == local.home_region_name)
}
