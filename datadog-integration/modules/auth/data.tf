data "oci_identity_user" "current_user" {
    # Required
    user_id = var.current_user_id
}
