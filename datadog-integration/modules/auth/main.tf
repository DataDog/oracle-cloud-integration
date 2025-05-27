terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
  }
}

locals {
  idcs_endpoint = data.oci_identity_domain.selected_domain.url
}

resource "oci_identity_domains_user" "dd_auth" {
  count = var.existing_user_id == null ? 1 : 0
  # Required
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User", "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"]
  user_name     = var.user_name
  emails {
    primary = true
    value   = local.email
    type    = "work"
  }
  name {
    family_name = var.user_name
    given_name  = var.user_name
  }
  display_name = var.user_name
}

resource "oci_identity_domains_group" "dd_auth" {
  count = var.existing_group_id == null ? 1 : 0
  # Required
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = local.user_group_name

  # Add user to group
  members {
    value = var.existing_user_id != null ? var.existing_user_id : oci_identity_domains_user.dd_auth[0].id
    type  = "User"
  }

}

resource "oci_identity_policy" "dd_auth" {
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policies required by Datadog User"
  name           = local.user_policy_name
  statements = [
    "Define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub",
    "Allow group ${var.existing_group_id != null ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].id} to read all-resources in tenancy",
    "Allow group ${var.existing_group_id != null ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].id} to manage serviceconnectors in compartment id ${var.compartment_id}",
    "Allow group ${var.existing_group_id != null ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].id} to manage functions-family in compartment id ${var.compartment_id} where ANY {request.permission = 'FN_FUNCTION_UPDATE', request.permission = 'FN_FUNCTION_LIST', request.permission = 'FN_APP_LIST'}",
    "Endorse group ${var.existing_group_id != null ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].id} to read objects in tenancy usage-report"
  ]
  freeform_tags = var.tags
}

resource "oci_identity_domains_dynamic_resource_group" "service_connector" {
  # Required
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]
  display_name  = local.dg_sch_name
  description   = "[DO NOT REMOVE] Dynamic group for forwarding by service connector"
  matching_rule = "All {resource.type = 'serviceconnector', resource.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_domains_dynamic_resource_group" "forwarding_function" {
  # Required
  idcs_endpoint = local.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]
  display_name  = local.dg_fn_name
  description   = "[DO NOT REMOVE] Dynamic group for forwarding functions"
  matching_rule = "All {resource.type = 'fnfunc', resource.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_policy" "dynamic_group" {
  depends_on     = [oci_identity_domains_dynamic_resource_group.service_connector]
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from eligible sources and write to a target function"
  name           = local.dg_policy_name
  statements = [
    "Allow dynamic-group ${oci_identity_domains_dynamic_resource_group.service_connector.id} to read log-content in tenancy",
    "Allow dynamic-group ${oci_identity_domains_dynamic_resource_group.service_connector.id} to read metrics in tenancy",
    "Allow dynamic-group ${oci_identity_domains_dynamic_resource_group.service_connector.id} to use fn-function in compartment id ${var.compartment_id}",
    "Allow dynamic-group ${oci_identity_domains_dynamic_resource_group.service_connector.id} to use fn-invocation in compartment id ${var.compartment_id}",
    "Allow dynamic-group ${oci_identity_domains_dynamic_resource_group.forwarding_function.id} to read secret-bundles in compartment id ${var.compartment_id}"
  ]
  freeform_tags = var.tags
}
