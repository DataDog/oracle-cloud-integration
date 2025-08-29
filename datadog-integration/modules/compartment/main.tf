terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
  }
}

# Conditional compartment logic
# Use existing compartment if provided, otherwise create new one
data "oci_identity_compartment" "existing" {
  count = var.compartment_id != null ? 1 : 0
  id    = var.compartment_id
}

resource "oci_identity_compartment" "new" {
  count          = var.compartment_id == null ? 1 : 0
  name           = var.new_compartment_name
  description    = "Compartment for Datadog generated resources"
  compartment_id = var.parent_compartment_id
  freeform_tags  = var.tags
}
