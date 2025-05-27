module "compartment" {
  source                = "./modules/compartment"
  compartment_name      = var.compartment_name
  parent_compartment_id = var.tenancy_ocid
  tags                  = local.tags
}

module "domain" {
  source = "./modules/domain"
  domain_name = var.domain_name
  tenancy_id  = var.tenancy_ocid
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
  compartment_id   = module.compartment.id
  idcs_endpoint    = module.domain.idcs_endpoint
  existing_user_id = var.existing_user_id
  existing_group_id = var.existing_group_id
}

module "key" {
  source           = "./modules/key"
  count            = var.region == local.home_region_name ? 1 : 0
  existing_user_id = module.auth[0].user_id
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = module.compartment.id
  region           = var.region
  idcs_endpoint    = module.domain.idcs_endpoint
  depends_on       = [module.auth]
}

module "integration" {
  depends_on = [module.auth, module.key, module.kms]
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


