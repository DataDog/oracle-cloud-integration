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
  matching_domain_id = (
    var.domain_id != null && var.domain_id != "" ?
    var.domain_id :
    [for k, v in data.oci_identity_domains_user.user_in_domain : k if v.active != null && v.emails != null][0]
  )

  matching_domain = [
    for d in data.oci_identity_domains.all_domains.domains : d
    if d.id == local.matching_domain_id
  ][0]

  user_email = (
    var.existing_user_id == null || var.existing_user_id == "" ?
    (
      var.user_email != null && var.user_email != "" ?
      var.user_email:
      data.oci_identity_domains_user.user_in_domain[local.matching_domain_id].emails[0].value
    ) :
    null
  )

  domain_display_name = local.matching_domain.display_name
  idcs_endpoint       = local.matching_domain.url

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

  # Convert multiline string to list of subnet OCIDs (remove any trailing periods)
  # First pass: get cleaned lines
  subnet_ocids_raw = [
    for line in split("\n", var.subnet_ocids) :
    trimspace(line) if trimspace(line) != ""
  ]

  # Second pass: remove trailing periods manually (compatible with Terraform <= 1.5.x)
  subnet_ocids_list = [
    for ocid in local.subnet_ocids_raw :
    length(ocid) > 0 && substr(ocid, length(ocid) - 1, 1) == "." ? substr(ocid, 0, length(ocid) - 1) : ocid
  ]

  # Create mapping from region key (3-letter code) to full region name
  region_key_to_name_map = {
    for region in local.subscribed_regions :
    region.region_key => region.region_name
  }

  # Subnet OCID to normalized region name mapping (handles both full names and 3-letter codes)
  subnet_ocid_to_region_map = {
    for subnet_ocid in local.subnet_ocids_list :
    subnet_ocid => (
    # Safely get the region identifier from OCID (position 3), with bounds checking
      length(split(".", subnet_ocid)) >= 4 ? (
    # Convert region identifier to uppercase for lookup (OCIDs contain lowercase, but region_key is uppercase)
      contains(keys(local.region_key_to_name_map), upper(split(".", subnet_ocid)[3])) ?
      # If it's a 3-letter code, convert to full name using uppercase lookup
      local.region_key_to_name_map[upper(split(".", subnet_ocid)[3])] :
      # Check if it's already a full region name in our subscribed regions
        contains(local.subscribed_regions_set, split(".", subnet_ocid)[3]) ?
        split(".", subnet_ocid)[3] :
        # Otherwise mark as unknown for validation
        "unknown-region-${split(".", subnet_ocid)[3]}"
    ) : "invalid-region"
    )
  }

  # Get unique normalized region names from provided subnet OCIDs
  subnet_regions = toset(values(local.subnet_ocid_to_region_map))

  # Region to subnet OCID mapping (takes first subnet OCID per region)
  region_to_subnet_ocid_map = {
    for region_name in local.subnet_regions :
    region_name => [
      for subnet_ocid, mapped_region in local.subnet_ocid_to_region_map :
      subnet_ocid if mapped_region == region_name
    ][0]
  }

  # Validate that all subnet regions are subscribed regions
  # Note: subnet_regions contains normalized full region names, so we compare against subscribed regions
  unsubscribed_subnet_regions = setsubtract(local.subnet_regions, local.subscribed_regions_set)

  # Validation helpers for check blocks
  invalid_format_ocids = [
    for ocid in local.subnet_ocids_list : ocid
    if !can(regex("^ocid1\\.subnet\\.oc[0-9]\\.[a-zA-Z0-9-]+\\.[a-zA-Z0-9]+$", ocid))
  ]

  duplicate_ocids = [
    for ocid in local.subnet_ocids_list : ocid
    if length([for o in local.subnet_ocids_list : o if o == ocid]) > 1
  ]

  invalid_structure_ocids = [
    for ocid in local.subnet_ocids_list : ocid
    if length(split(".", ocid)) != 5
  ]

  duplicate_regions = [
    for ocid in local.subnet_ocids_list : ocid
    if length([
      for o in local.subnet_ocids_list : o
      if length(split(".", o)) >= 4 && length(split(".", ocid)) >= 4 && split(".", o)[3] == split(".", ocid)[3]
    ]) > 1
  ]

  docker_image_enabled_regions = toset([
    for region in local.subscribed_regions_list : region
    if local.supported_regions[region].result.failure == ""
  ])

  # Intersection of subscribed regions, regions in domain, subnet regions (compatible with Terraform <= 1.5.x)
  # Only create regional stacks for regions that meet all three criteria
  target_regions_for_stacks = length(local.subnet_ocids_list) > 0 ? toset([
    for region in local.subscribed_regions_list : region
    if contains(tolist(local.regions_in_domain_set), region) && contains(tolist(local.subnet_regions), region)
  ]) : toset([
    for region in local.subscribed_regions_list : region if contains(tolist(local.regions_in_domain_set), region)
  ])

  # final set reported to Datadog
  final_regions_for_stacks = toset([
    for region in local.target_regions_for_stacks : region
    if contains(tolist(local.docker_image_enabled_regions), region)
  ])

}
