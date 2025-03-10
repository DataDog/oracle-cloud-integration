terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

resource "oci_identity_user" "dd_auth_user" {
  # Required
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Read only user created for fetching resources metadata which is used by Datadog Integrations"
  name           = var.user_name
  email          = local.email
  freeform_tags  = var.tags
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "oci_identity_api_key" "this" {
  user_id   = oci_identity_user.dd_auth_user.id
  key_value = tls_private_key.this.public_key_pem
}

resource "oci_identity_group" "user_group" {
  # Required
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Group for adding permissions to Datadog user"
  name           = local.user_group_name
  freeform_tags  = var.tags
}

resource "oci_identity_user_group_membership" "dd_user_group_membership" {
  # Required
  group_id = oci_identity_group.user_group.id
  user_id  = oci_identity_user.dd_auth_user.id
}

resource "oci_identity_policy" "dd_auth_policy" {
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policies required by Datadog User"
  name           = local.user_policy_name
  statements = [
    "Allow group ${oci_identity_group.user_group.name} to read all-resources in tenancy",
    "Allow group ${oci_identity_group.user_group.name} to manage all-resources in compartment ${var.compartment_name}"
  ]
  freeform_tags = var.tags
}

resource "oci_identity_dynamic_group" "sch_dg" {
  count = var.forward_metrics || var.forward_logs ? 1 : 0
  # Required
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Dynamic group for forwarding by service connector"
  matching_rule  = "All {resource.type = 'serviceconnector', resource.compartment.id = '${var.compartment_id}'}"
  name           = local.dg_name
  freeform_tags  = var.tags
}

resource "oci_identity_policy" "dg_policy" {
  depends_on     = [oci_identity_dynamic_group.sch_dg]
  count          = var.forward_metrics || var.forward_logs ? 1 : 0
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from eligible sources and write to a target function"
  name           = local.dg_policy_name
  statements = concat(
    var.forward_logs ? ["Allow dynamic-group Default/${local.dg_name} to read log-content in tenancy"] : [],
    var.forward_metrics ? ["Allow dynamic-group Default/${local.dg_name} to read metrics in tenancy"] : [],
    [
      "Allow dynamic-group Default/${local.dg_name} to use fn-function in compartment ${var.compartment_name}",
      "Allow dynamic-group Default/${local.dg_name} to use fn-invocation in compartment ${var.compartment_name}",
      "Allow dynamic-group Default/${local.dg_name} to read secret-bundles in compartment ${var.compartment_name}"
    ]
  )
  freeform_tags = var.tags
}
