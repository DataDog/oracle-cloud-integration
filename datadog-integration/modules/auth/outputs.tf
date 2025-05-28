output "user_id" {
  value = oci_identity_user.dd_auth.id
}

output "group_id" {
  value = oci_identity_group.dd_auth.id
}
