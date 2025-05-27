terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
  }
}

# Look up existing compartment
data "oci_identity_compartments" "existing" {
  compartment_id = var.parent_compartment_id
  filter {
    name   = "name"
    values = [var.compartment_name]
  }
}

# Create compartment only if it doesn't exist
resource "oci_identity_compartment" "this" {
  count          = length(data.oci_identity_compartments.existing.compartments) > 0 ? 0 : 1
  name           = var.compartment_name
  description    = "Compartment for Datadog generated resources"
  compartment_id = var.parent_compartment_id
  freeform_tags  = var.tags
}

# Local to determine which compartment ID to use
locals {
  compartment_id = length(data.oci_identity_compartments.existing.compartments) > 0 ? data.oci_identity_compartments.existing.compartments[0].id : oci_identity_compartment.this[0].id
}
