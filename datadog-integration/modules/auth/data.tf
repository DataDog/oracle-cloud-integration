data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_id
}

# optional: if a user is provided, we will not create a new one
data "oci_identity_domains_users" "existing_user" {
  count          = var.existing_user_id != null ? 1 : 0
  idcs_endpoint  = var.idcs_endpoint
  attribute_sets = ["all"]
  attributes     = "id eq \"${var.existing_user_id}\""
}

# optional: if a group is provided, we will not create a new one
data "oci_identity_domains_groups" "existing_group" {
  count          = var.existing_group_id != null ? 1 : 0
  idcs_endpoint  = var.idcs_endpoint
  attribute_sets = ["all"]
  attributes     = "id eq \"${var.existing_group_id}\""
}
