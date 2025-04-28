locals {
  user_name        = "${var.user_name}-${random_string.random_string.result}"
  user_group_name  = "${local.user_name}-admin-${random_string.random_string.result}"
  user_policy_name = "${local.user_name}-policy-${random_string.random_string.result}"
  dg_sch_name      = "dd-dynamic-group-connectorhubs-${random_string.random_string.result}"
  dg_fn_name       = "dd-dynamic-group-functions-${random_string.random_string.result}"
  dg_policy_name   = "dd-dynamic-group-policy-${random_string.random_string.result}"
  matching_domain  = data.oci_identity_user.current_user.email == null ? [for k, v in data.oci_identity_domains_user.user_in_domain : k if v.emails != null][0] : null
  email            = data.oci_identity_user.current_user.email != null ? data.oci_identity_user.current_user.email : data.oci_identity_domains_user.user_in_domain[local.matching_domain].emails[0].value
}
