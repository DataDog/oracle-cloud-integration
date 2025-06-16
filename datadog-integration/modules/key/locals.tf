locals {
  user_id = var.existing_user_id
  # Always get the IDCS endpoint from the selected domain
  idcs_endpoint  = data.oci_identity_domain.selected_domain.url
  endpoint_param = "--endpoint ${local.idcs_endpoint}"
}
