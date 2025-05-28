data "oci_identity_region_subscriptions" "subscribed_regions" {
  tenancy_id = var.tenancy_ocid
}

data "external" "supported_regions" {
  for_each = local.subscribed_regions_map
  program  = ["bash", "${path.module}/docker_image_check.sh"]

  query = {
    region         = each.key
    regionKey      = each.value.region_key
  }
}

data "external" "pre_checks" {
  program = ["python3", "${path.module}/pre_check.py"]

  query = {
    tenancy_id = var.tenancy_ocid
    is_home_region = local.is_current_region_home_region
    supported_regions = jsonencode(local.supported_regions_list)
    user_id = var.current_user_ocid
    user_name = local.user_name
    user_group_name = local.user_group_name
    user_group_policy_name = local.user_group_policy_name
    dg_sch_name = local.dg_sch_name
    dg_fn_name = local.dg_fn_name
    dg_policy_name = local.dg_policy_name
  }
}