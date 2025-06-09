data "oci_identity_region_subscriptions" "subscribed_regions" {
  tenancy_id = var.tenancy_ocid
}

data "external" "supported_regions" {
  for_each = local.subscribed_regions_map
  program  = ["bash", "${path.module}/docker_image_check.sh"]

  query = {
    region    = each.key
    regionKey = each.value.region_key
  }
}

data "oci_identity_domains" "all_domains" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_domains_user" "user_in_domain" {
  for_each      = { for d in data.oci_identity_domains.all_domains.domains : d.id => d }
  idcs_endpoint = each.value.url
  user_id       = var.current_user_ocid
}
