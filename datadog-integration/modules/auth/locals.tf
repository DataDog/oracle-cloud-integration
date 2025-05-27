locals {
  user_group_name  = var.existing_user_id != null ? data.oci_identity_domains_user.current_user.user_name : "${var.user_name}-admin"
  user_policy_name = var.existing_user_id != null ? "${data.oci_identity_domains_user.current_user.user_name}-policy" : "${var.user_name}-policy"
  dg_sch_name      = "dd-dynamic-group-connectorhubs"
  dg_fn_name       = "dd-dynamic-group-functions"
  dg_policy_name   = "dd-dynamic-group-policy"
  email            = data.oci_identity_domains_user.current_user.emails[0].value
}
