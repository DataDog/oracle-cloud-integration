data "oci_identity_region_subscriptions" "subscribed_regions" {
  tenancy_id = var.tenancy_ocid
}
