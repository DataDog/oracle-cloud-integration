data "oci_identity_user" "current_user" {
    user_id = var.current_user_ocid
}

data "oci_identity_domains" "all_domains" {
    count = data.oci_identity_user.current_user.email == null ? 1 : 0
    compartment_id = var.tenancy_ocid
}

data "oci_identity_domains_user" "user_in_domain" {
    for_each = length(data.oci_identity_domains.all_domains) > 0 ? { for d in data.oci_identity_domains.all_domains[0].domains : d.id => d } : {}
    idcs_endpoint = each.value.url
    user_id       = var.current_user_ocid
}

locals {
  matching_domain = data.oci_identity_user.current_user.email == null ? [for k, v in data.oci_identity_domains_user.user_in_domain : k if v.emails != null][0] : null
  email = data.oci_identity_user.current_user.email != null ? data.oci_identity_user.current_user.email : data.oci_identity_domains_user.user_in_domain[local.matching_domain].emails[0].value
}
