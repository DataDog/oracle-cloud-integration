module "compartment" {
  source                = "./modules/compartment"
  compartment_name      = local.compartment_name
  parent_compartment_id = var.tenancy_ocid
  tags                  = local.tags
}

module "kms" {
  source          = "./modules/kms"
  count           = var.region == local.home_region_name ? 1 : 0
  compartment_id  = module.compartment.id
  datadog_api_key = var.datadog_api_key
  tags            = local.tags
}

module "auth" {
  source           = "./modules/auth"
  count            = var.region == local.home_region_name ? 1 : 0
  user_name        = local.user_name
  tenancy_id       = var.tenancy_ocid
  tags             = local.tags
  current_user_id  = var.current_user_ocid
  compartment_name = local.compartment_name
  compartment_id   = module.compartment.id
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
  private_key                     = module.auth[0].private_key
  public_key_finger_print         = module.auth[0].public_key_fingerprint
  user_ocid                       = module.auth[0].user_id
  subscribed_regions              = local.supported_regions_list
  datadog_resource_compartment_id = module.compartment.id
}


