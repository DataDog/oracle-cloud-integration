locals {
  user_id = var.existing_user_id
  # Use the IDCS endpoint passed from parent module
  idcs_endpoint  = var.idcs_endpoint
  endpoint_param = "--endpoint ${local.idcs_endpoint}"
}
