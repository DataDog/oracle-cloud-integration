terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "7.0.0"
    }
  }
}

resource "oci_identity_compartment" "this" {
  name           = var.compartment_name
  description    = "Compartment for Datadog generated resources"
  compartment_id = var.parent_compartment_id
  freeform_tags  = var.tags
}
