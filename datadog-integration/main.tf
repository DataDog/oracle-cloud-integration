resource "null_resource" "precheck_marker" {
  provisioner "local-exec" {
    when    = create
    on_failure = fail
    command = <<-EOT
      python ${path.module}/pre_check.py \
        --tenancy-id '${var.tenancy_ocid}' \
        --is-home-region '${local.is_current_region_home_region}' \
        --home-region '${local.home_region_name}' \
        --supported-regions '${jsonencode(local.supported_regions_list)}' \
        --user-id '${var.current_user_ocid}' \
        --user-name '${local.user_name}' \
        --user-group-name '${local.user_group_name}' \
        --user-group-policy-name '${local.user_group_policy_name}' \
        --dg-sch-name '${local.dg_sch_name}' \
        --dg-fn-name '${local.dg_fn_name}' \
        --dg-policy-name '${local.dg_policy_name}' \
        --domain-display-name '${local.domain_display_name}' \
        --idcs-endpoint '${local.idcs_endpoint}'
    EOT
  }
}

module "compartment" {
  depends_on = [null_resource.precheck_marker]
  source                = "./modules/compartment"
  compartment_name      = local.compartment_name
  parent_compartment_id = var.tenancy_ocid
  tags                  = local.tags
}

module "kms" {
  depends_on = [null_resource.precheck_marker]
  source          = "./modules/kms"
  count           = local.is_current_region_home_region ? 1 : 0
  compartment_id  = module.compartment.id
  datadog_api_key = var.datadog_api_key
  tags            = local.tags
}

module "auth" {
  depends_on = [null_resource.precheck_marker]
  source           = "./modules/auth"
  count            = local.is_current_region_home_region ? 1 : 0
  user_name        = local.user_name
  tenancy_id       = var.tenancy_ocid
  tags             = local.tags
  current_user_id  = var.current_user_ocid
  compartment_name = local.compartment_name
  compartment_id   = module.compartment.id
  user_group_name           = local.user_group_name
  user_group_policy_name    = local.user_group_policy_name
  dg_sch_name              = local.dg_sch_name
  dg_fn_name               = local.dg_fn_name
  dg_policy_name           = local.dg_policy_name
  email                    = local.email
}

module "key" {
  source           = "./modules/key"
  count            = local.is_current_region_home_region ? 1 : 0
  existing_user_id = module.auth[0].user_id
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = module.compartment.id
  region           = var.region
  depends_on       = [module.auth]
}

module "integration" {
  depends_on = [module.kms]
  source     = "./modules/integration"
  providers = {
    restapi = restapi
  }
  count                           = local.is_current_region_home_region ? 1 : 0
  datadog_api_key                 = var.datadog_api_key
  datadog_app_key                 = var.datadog_app_key
  datadog_site                    = var.datadog_site
  home_region                     = local.home_region_name
  tenancy_ocid                    = var.tenancy_ocid
  private_key                     = module.key[0].private_key
  user_ocid                       = module.auth[0].user_id
  subscribed_regions              = local.supported_regions_list
  datadog_resource_compartment_id = module.compartment.id
}
