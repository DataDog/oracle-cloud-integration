terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

data "oci_identity_tenancy" "tenancy_metadata" {
  tenancy_id = var.tenancy_ocid
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
}

locals {
  tenancy_home_region    = data.oci_identity_tenancy.tenancy_metadata.home_region_key
  datadog_metrics_policy = "datadog-policy-metrics"
  dd_auth_user           = "DatadogROAuthUser"
  dd_auth_write_user     = "DatadogAuthWriteUser"
  dynamic_group_name     = "datadog-dynamic-group"
  user_group_name        = "DatadogAuthGroup"
  user_write_group_name  = "DatadogAuthWriteGroup"
  freeform_tags = {
    datadog-terraform = "true"
  }
}

resource "oci_identity_dynamic_group" "serviceconnector_group" {
  #Required
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Dynamic group for service connector"
  matching_rule  = "All {resource.type = 'serviceconnector'}"
  name           = local.dynamic_group_name

  #Optional
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

resource "oci_identity_user" "read_only_user" {
  #Required
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Read only user created for fetching resources metadata which is used by Datadog Integrations"
  name           = local.dd_auth_user
  email          = "test@datadoghq.com"

  #Optional
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

resource "oci_identity_user" "write_permissions_user" {
  #Required
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] User for performing write based operations like docker image push"
  name           = local.dd_auth_write_user
  email          = "test@oci.com"

  #Optional
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

resource "oci_identity_group" "read_policy_group" {
  depends_on = [oci_identity_user.read_only_user]
  #Required
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Group for adding a user for having read-only permissions of resources"
  name           = local.user_group_name

  #Optional
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

resource "oci_identity_group" "write_user_group" {
  depends_on = [oci_identity_user.write_permissions_user]
  #Required
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Group for adding a user for having read-only permissions of resources"
  name           = local.user_write_group_name

  #Optional
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

resource "oci_identity_user_group_membership" "dd_user_group_membership" {
  depends_on = [oci_identity_user.read_only_user, oci_identity_group.read_policy_group]
  #Required
  group_id = oci_identity_group.read_policy_group.id
  user_id  = oci_identity_user.read_only_user.id
}

resource "oci_identity_user_group_membership" "dd_write_user_group_membership" {
  depends_on = [oci_identity_user.write_permissions_user, oci_identity_group.write_user_group]
  #Required
  group_id = oci_identity_group.write_user_group.id
  user_id  = oci_identity_user.write_permissions_user.id
}

resource "oci_identity_policy" "metrics_policy" {
  depends_on     = [oci_identity_dynamic_group.serviceconnector_group, oci_identity_user_group_membership.dd_user_group_membership]
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from monitoring source and write to a target function"
  name           = local.datadog_metrics_policy
  statements = ["Allow dynamic-group Default/${local.dynamic_group_name} to read metrics in tenancy",
    "Allow dynamic-group Default/${local.dynamic_group_name} to use fn-function in tenancy",
    "Allow dynamic-group Default/${local.dynamic_group_name} to use fn-invocation in tenancy",
    "Allow group Default/${oci_identity_group.read_policy_group.name} to read all-resources in tenancy",
    "Allow group Default/${oci_identity_group.write_user_group.name} to manage repos in tenancy where ANY {request.permission = 'REPOSITORY_READ', request.permission = 'REPOSITORY_UPDATE', request.permission = 'REPOSITORY_CREATE'}"
  ]
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}
