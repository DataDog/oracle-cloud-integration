locals {
  tags = {
    ownedby = "datadog"
  }

  compartment_name = "Datadog"
  user_name        = "dd-svc"

  home_region_name = [
    for region in data.oci_identity_regions.all_regions.regions : region.name
    if region.key == data.oci_identity_tenancy.tenancy_metadata.home_region_key
  ][0]
}
