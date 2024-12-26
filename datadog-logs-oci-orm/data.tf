# Source from https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_region_subscriptions

data "oci_identity_region_subscriptions" "subscriptions" {
  # Required
  provider   = oci.home
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_tenancy" "tenancy_metadata" {
  tenancy_id = var.tenancy_ocid
}

data "external" "logging_services" {
    program = ["bash", "logging_services.sh"]
}
