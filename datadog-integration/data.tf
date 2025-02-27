data "oci_identity_tenancy" "tenancy_metadata" {
    tenancy_id = var.tenancy_ocid
}

data "oci_identity_regions" "all_regions" {
}
