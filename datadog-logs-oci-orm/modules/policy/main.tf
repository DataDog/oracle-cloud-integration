resource "oci_identity_dynamic_group" "serviceconnector_group" {
  #Required
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Dynamic group for log forwarding by service connector"
  matching_rule  = "All {resource.type = 'serviceconnector'}"
  name           = local.dynamic_group_name

  #Optional
  defined_tags  = {}
  freeform_tags = var.freeform_tags
}

resource "oci_identity_policy" "logs_policy" {
  depends_on     = [oci_identity_dynamic_group.serviceconnector_group]
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from logging source and write to a target function"
  name           = local.policy_name
  statements = ["Allow dynamic-group Default/${local.dynamic_group_name} to read log-content in tenancy",
    "Allow dynamic-group Default/${local.dynamic_group_name} to use fn-function in tenancy",
    "Allow dynamic-group Default/${local.dynamic_group_name} to use fn-invocation in tenancy"
  ]
  defined_tags  = {}
  freeform_tags = var.freeform_tags
}
