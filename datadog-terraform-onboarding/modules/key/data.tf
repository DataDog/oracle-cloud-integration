data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_ocid
}
