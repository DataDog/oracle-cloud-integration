locals {
  user_group_name  = "dd-svc-user-group"
  user_policy_name = "dd-svc-user-policy"
  dg_sch_name      = "dd-dynamic-group-connectorhubs"
  dg_fn_name       = "dd-dynamic-group-functions"
  dg_policy_name   = "dd-dynamic-group-policy"
  email            = data.oci_identity_domains_user.current_user.emails[0].value
}
