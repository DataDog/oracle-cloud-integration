data "oci_identity_region_subscriptions" "subscribed_regions" {
  tenancy_id = var.tenancy_ocid
}

data "external" "supported_regions" {
  for_each = local.subscribed_regions_map
  program  = ["bash", "${path.module}/docker_image_check.sh"]

  query = {
    region         = each.key
    regionKey      = each.value.region_key
    compartment-id = module.compartment.id
  }
}
