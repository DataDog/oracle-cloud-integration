
# Local value to provide the correct compartment ID
locals {
  compartment_id   = var.compartment_id != null ? var.compartment_id : oci_identity_compartment.new[0].id
  compartment_name = var.compartment_id != null ? data.oci_identity_compartment.existing[0].name : oci_identity_compartment.new[0].name
}
