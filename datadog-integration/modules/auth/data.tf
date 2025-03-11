data "oci_identity_user" "current_user" {
  # Required
  user_id = var.current_user_id
}

data "oci_identity_domains" "all_domains" {
  count          = data.oci_identity_user.current_user.email == null ? 1 : 0
  compartment_id = var.tenancy_id
}

data "oci_identity_domains_user" "user_in_domain" {
  for_each      = length(data.oci_identity_domains.all_domains) > 0 ? { for d in data.oci_identity_domains.all_domains[0].domains : d.id => d } : {}
  idcs_endpoint = each.value.url
  user_id       = var.current_user_id
}
