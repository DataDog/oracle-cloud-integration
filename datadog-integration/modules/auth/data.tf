data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_id
}

data "oci_identity_domains" "domains" {
  compartment_id = var.tenancy_id
}

data "oci_identity_domain" "selected_domain" {
  domain_id = [for domain in data.oci_identity_domains.domains.domains : domain.id if domain.display_name == var.domain_name][0]
}

data "oci_identity_domains_user" "current_user" {
  idcs_endpoint = data.oci_identity_domain.selected_domain.url
  user_id = var.current_user_id
}

data "oci_identity_domains_users" "existing_user" {
  count = var.existing_user_id != null ? 1 : 0
  idcs_endpoint = data.oci_identity_domain.selected_domain.url
  attribute_sets = ["all"]
  attributes = "id eq \"${var.existing_user_id}\""
}

data "oci_identity_domains_groups" "existing_group" {
  count = var.existing_group_id != null ? 1 : 0
  idcs_endpoint = data.oci_identity_domain.selected_domain.url
  attribute_sets = ["all"]
  attributes = "id eq \"${var.existing_group_id}\""
}
