data "external" "logging_services" {
    program = ["bash", "logging_services.sh"]
}

data "oci_identity_tenancy" "tenancy_metadata" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_regions" "all_regions" {
}
