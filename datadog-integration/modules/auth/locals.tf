locals {
  email         = var.user_email
  dd_group_ocid = var.existing_group_id != null && var.existing_group_id != "" ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].ocid
}
