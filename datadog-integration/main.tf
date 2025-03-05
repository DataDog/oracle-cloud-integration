module "compartment" {
  source                  = "./modules/compartment"
  compartment_name        = local.compartment_name
  parent_compartment_id   = var.tenancy_ocid
  tags                    = local.tags
}

module "auth" {
  source                  = "./modules/auth"
  count                   = var.region == local.home_region_name ? 1 : 0
  user_name               = local.user_name
  tenancy_id              = var.tenancy_ocid
  tags                    = local.tags
  current_user_id         = var.current_user_ocid
  compartment_name        = local.compartment_name
  compartment_id          = module.compartment.id
  forward_metrics         = var.metrics_image_tag != "" ? true : false
  forward_logs            = var.logs_image_tag != "" ? true : false
}

module "networking" {
  source                  = "./modules/networking"
  compartment_id          = module.compartment.id
  tags                    = local.tags
}

module "functions" {
  source                  = "./modules/functions"
  region                  = var.region
  tenancy_id              = var.tenancy_ocid
  compartment_id          = module.compartment.id
  subnet_id               = module.networking.subnet_id
  tags                    = local.tags
  metrics_image_tag       = var.metrics_image_tag
  logs_image_tag          = var.logs_image_tag
  datadog_site            = var.datadog_site
}

module "integration" {
  source = "./modules/integration"
  providers = {
    restapi = restapi
  }
  count                   = var.region == local.home_region_name ? 1 : 0
  datadog_api_key         = var.datadog_api_key
  datadog_app_key         = var.datadog_app_key
  datadog_site            = var.datadog_site
  home_region             = local.home_region_name
  tenancy_ocid            = var.tenancy_ocid
  private_key             = module.auth[0].private_key
  public_key_finger_print = module.auth[0].public_key_fingerprint
  user_ocid               = module.auth[0].user_id
}
