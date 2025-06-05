locals {
  tags = {
    ownedby = "datadog"
  }

  home_region_name = [
    for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]

  is_current_region_home_region = (var.region == local.home_region_name)

  new_compartment_name = "Datadog"
}

#Auth Variables
locals {
  user_name              = "dd-svc"
  user_group_name        = "${local.user_name}-admin"
  user_group_policy_name = "${local.user_name}-policy"
  dg_sch_name            = "dd-dynamic-group-connectorhubs"
  dg_fn_name             = "dd-dynamic-group-functions"
  dg_policy_name         = "dd-dynamic-group-policy"
  matching_domain_id     = [for k, v in data.oci_identity_domains_user.user_in_domain : k if v.emails != null][0]
  matching_domain = [
    for d in data.oci_identity_domains.all_domains.domains : d
    if d.id == local.matching_domain_id
  ][0]
  user_email = data.oci_identity_domains_user.user_in_domain[local.matching_domain_id].emails[0].value

  domain_display_name = local.matching_domain.display_name
  idcs_endpoint       = local.matching_domain.url

  # Domain-specific values (previously from domain module)
  domain_idcs_endpoint = data.oci_identity_domain.domain.url

  actual_user_name  = (var.existing_user_id == null || var.existing_user_id == "") ? local.user_name : null
  actual_group_name = (var.existing_group_id == null || var.existing_group_id == "") ? local.user_group_name : null
}

# Variables for regions
locals {
  subscribed_regions      = [for region in data.oci_identity_region_subscriptions.subscribed_regions.region_subscriptions : region]
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

  # regions in domain
  regions_in_domain     = flatten([[data.oci_identity_domain.domain.home_region], [for region in data.oci_identity_domain.domain.replica_regions : region.region]])
  regions_in_domain_set = toset(local.regions_in_domain)
}
