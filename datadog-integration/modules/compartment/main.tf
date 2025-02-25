resource "oci_identity_compartment" "this" {
  name           = var.compartment_name
  description    = "Compartment for Datadog generated resources"
  compartment_id = var.parent_compartment_id
  freeform_tags  = var.tags
}
