terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
  }
}

resource "oci_identity_user" "dd_auth" {
  # Required
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Read only user created for fetching resources metadata which is used by Datadog Integrations"
  name           = var.user_name
  email          = local.email
  freeform_tags  = var.tags
}

resource "oci_identity_group" "dd_auth" {
  # Required
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Group for adding permissions to Datadog user"
  name           = local.user_group_name
  freeform_tags  = var.tags
}

resource "oci_identity_user_group_membership" "dd_user_group_membership" {
  # Required
  group_id = oci_identity_group.dd_auth.id
  user_id  = oci_identity_user.dd_auth.id
}

resource "oci_identity_policy" "dd_auth" {
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policies required by Datadog User"
  name           = local.user_policy_name
  statements = [
    "Define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub",
    "Allow group ${oci_identity_group.dd_auth.name} to read all-resources in tenancy",
    "Allow group ${oci_identity_group.dd_auth.name} to manage serviceconnectors in compartment ${var.compartment_name}",
    "Allow group ${oci_identity_group.dd_auth.name} to manage functions-family in compartment ${var.compartment_name} where ANY {request.permission = 'FN_FUNCTION_UPDATE', request.permission = 'FN_FUNCTION_LIST', request.permission = 'FN_APP_LIST'}",
    "Endorse group ${oci_identity_group.dd_auth.name} to read objects in tenancy usage-report"
  ]
  freeform_tags = var.tags
}

resource "oci_identity_dynamic_group" "service_connector" {
  # Required
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Dynamic group for forwarding by service connector"
  matching_rule  = "All {resource.type = 'serviceconnector', resource.compartment.id = '${var.compartment_id}'}"
  name           = local.dg_sch_name
  freeform_tags  = var.tags
}

resource "oci_identity_dynamic_group" "forwarding_function" {
  # Required
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Dynamic group for forwarding functions"
  matching_rule  = "All {resource.type = 'fnfunc', resource.compartment.id = '${var.compartment_id}'}"
  name           = local.dg_fn_name
  freeform_tags  = var.tags
}

resource "oci_identity_policy" "dynamic_group" {
  depends_on     = [oci_identity_dynamic_group.service_connector]
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from eligible sources and write to a target function"
  name           = local.dg_policy_name
  statements = ["Allow dynamic-group Default/${local.dg_sch_name} to read log-content in tenancy",
    "Allow dynamic-group Default/${local.dg_sch_name} to read metrics in tenancy",
    "Allow dynamic-group Default/${local.dg_sch_name} to use fn-function in compartment ${var.compartment_name}",
    "Allow dynamic-group Default/${local.dg_sch_name} to use fn-invocation in compartment ${var.compartment_name}",
    "Allow dynamic-group Default/${local.dg_fn_name} to read secret-bundles in compartment ${var.compartment_name}"
  ]
  freeform_tags = var.tags
}
