locals {
    user_group_name = "${var.user_name}-admin"
    user_policy_name = "${var.user_name}-policy"
    dg_name = "dd-sch-dg"
    dg_policy_name = "${local.dg_name}-policy"
    email = data.oci_identity_user.current_user.email
}
