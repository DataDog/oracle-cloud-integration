locals {
  user_group_name  = "${var.user_name}-admin"
  user_policy_name = "${var.user_name}-policy"
  dg_sch_name      = "dd-dynamic-group-connectorhubs"
  dg_fn_name       = "dd-dynamic-group-functions"
  dg_policy_name   = "dd-dynamic-group-policy"
  matching_domain  = data.oci_identity_user.current_user.email == null ? [for k, v in data.oci_identity_domains_user.user_in_domain : k if v.emails != null][0] : null
  email            = data.oci_identity_user.current_user.email != null ? data.oci_identity_user.current_user.email : data.oci_identity_domains_user.user_in_domain[local.matching_domain].emails[0].value
}
