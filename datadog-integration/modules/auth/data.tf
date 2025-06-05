data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_id
}

# Get existing group by OCID (only when group OCID is provided and not empty)
data "oci_identity_domains_groups" "existing_group" {
  count         = var.existing_group_id != null && var.existing_group_id != "" ? 1 : 0
  idcs_endpoint = var.idcs_endpoint
  group_filter  = "ocid eq \"${var.existing_group_id}\""
}

# Get user by OCID with group memberships (when user OCID is provided and not empty)
data "oci_identity_domains_users" "existing_user_with_groups" {
  count        = var.existing_user_id != null && var.existing_user_id != "" ? 1 : 0
  idcs_endpoint = var.idcs_endpoint
  user_filter  = "ocid eq \"${var.existing_user_id}\""
  attributes   = "groups"
}
