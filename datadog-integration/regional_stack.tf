#
# Regional Deployment Modules
#
# Deploys Datadog forwarding infrastructure to each subscribed region.
# Uses static module blocks with provider aliases to enable multi-region deployment.
# Only regions that are subscribed and have Docker images will actually be deployed (count = 1).
#

module "regional_deployment_af_johannesburg_1" {
  count  = contains(local.final_regions_for_stacks, "af-johannesburg-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.af-johannesburg-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "af-johannesburg-1"
  region_key        = local.subscribed_regions_map["af-johannesburg-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "af-johannesburg-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_batam_1" {
  count  = contains(local.final_regions_for_stacks, "ap-batam-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-batam-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-batam-1"
  region_key        = local.subscribed_regions_map["ap-batam-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-batam-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_chuncheon_1" {
  count  = contains(local.final_regions_for_stacks, "ap-chuncheon-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-chuncheon-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-chuncheon-1"
  region_key        = local.subscribed_regions_map["ap-chuncheon-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-chuncheon-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_hyderabad_1" {
  count  = contains(local.final_regions_for_stacks, "ap-hyderabad-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-hyderabad-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-hyderabad-1"
  region_key        = local.subscribed_regions_map["ap-hyderabad-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-hyderabad-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_melbourne_1" {
  count  = contains(local.final_regions_for_stacks, "ap-melbourne-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-melbourne-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-melbourne-1"
  region_key        = local.subscribed_regions_map["ap-melbourne-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-melbourne-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_mumbai_1" {
  count  = contains(local.final_regions_for_stacks, "ap-mumbai-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-mumbai-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-mumbai-1"
  region_key        = local.subscribed_regions_map["ap-mumbai-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-mumbai-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_osaka_1" {
  count  = contains(local.final_regions_for_stacks, "ap-osaka-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-osaka-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-osaka-1"
  region_key        = local.subscribed_regions_map["ap-osaka-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-osaka-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_seoul_1" {
  count  = contains(local.final_regions_for_stacks, "ap-seoul-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-seoul-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-seoul-1"
  region_key        = local.subscribed_regions_map["ap-seoul-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-seoul-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_singapore_1" {
  count  = contains(local.final_regions_for_stacks, "ap-singapore-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-singapore-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-singapore-1"
  region_key        = local.subscribed_regions_map["ap-singapore-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-singapore-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_singapore_2" {
  count  = contains(local.final_regions_for_stacks, "ap-singapore-2") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-singapore-2
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-singapore-2"
  region_key        = local.subscribed_regions_map["ap-singapore-2"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-singapore-2", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_sydney_1" {
  count  = contains(local.final_regions_for_stacks, "ap-sydney-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-sydney-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-sydney-1"
  region_key        = local.subscribed_regions_map["ap-sydney-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-sydney-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ap_tokyo_1" {
  count  = contains(local.final_regions_for_stacks, "ap-tokyo-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ap-tokyo-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ap-tokyo-1"
  region_key        = local.subscribed_regions_map["ap-tokyo-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ap-tokyo-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ca_montreal_1" {
  count  = contains(local.final_regions_for_stacks, "ca-montreal-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ca-montreal-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ca-montreal-1"
  region_key        = local.subscribed_regions_map["ca-montreal-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ca-montreal-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_ca_toronto_1" {
  count  = contains(local.final_regions_for_stacks, "ca-toronto-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.ca-toronto-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "ca-toronto-1"
  region_key        = local.subscribed_regions_map["ca-toronto-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "ca-toronto-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_amsterdam_1" {
  count  = contains(local.final_regions_for_stacks, "eu-amsterdam-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-amsterdam-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-amsterdam-1"
  region_key        = local.subscribed_regions_map["eu-amsterdam-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-amsterdam-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_frankfurt_1" {
  count  = contains(local.final_regions_for_stacks, "eu-frankfurt-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-frankfurt-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-frankfurt-1"
  region_key        = local.subscribed_regions_map["eu-frankfurt-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-frankfurt-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_madrid_1" {
  count  = contains(local.final_regions_for_stacks, "eu-madrid-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-madrid-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-madrid-1"
  region_key        = local.subscribed_regions_map["eu-madrid-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-madrid-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_marseille_1" {
  count  = contains(local.final_regions_for_stacks, "eu-marseille-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-marseille-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-marseille-1"
  region_key        = local.subscribed_regions_map["eu-marseille-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-marseille-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_milan_1" {
  count  = contains(local.final_regions_for_stacks, "eu-milan-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-milan-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-milan-1"
  region_key        = local.subscribed_regions_map["eu-milan-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-milan-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_paris_1" {
  count  = contains(local.final_regions_for_stacks, "eu-paris-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-paris-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-paris-1"
  region_key        = local.subscribed_regions_map["eu-paris-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-paris-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_stockholm_1" {
  count  = contains(local.final_regions_for_stacks, "eu-stockholm-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-stockholm-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-stockholm-1"
  region_key        = local.subscribed_regions_map["eu-stockholm-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-stockholm-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_eu_zurich_1" {
  count  = contains(local.final_regions_for_stacks, "eu-zurich-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.eu-zurich-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "eu-zurich-1"
  region_key        = local.subscribed_regions_map["eu-zurich-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "eu-zurich-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_il_jerusalem_1" {
  count  = contains(local.final_regions_for_stacks, "il-jerusalem-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.il-jerusalem-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "il-jerusalem-1"
  region_key        = local.subscribed_regions_map["il-jerusalem-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "il-jerusalem-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_me_abudhabi_1" {
  count  = contains(local.final_regions_for_stacks, "me-abudhabi-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.me-abudhabi-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "me-abudhabi-1"
  region_key        = local.subscribed_regions_map["me-abudhabi-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "me-abudhabi-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_me_dubai_1" {
  count  = contains(local.final_regions_for_stacks, "me-dubai-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.me-dubai-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "me-dubai-1"
  region_key        = local.subscribed_regions_map["me-dubai-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "me-dubai-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_me_jeddah_1" {
  count  = contains(local.final_regions_for_stacks, "me-jeddah-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.me-jeddah-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "me-jeddah-1"
  region_key        = local.subscribed_regions_map["me-jeddah-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "me-jeddah-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_me_riyadh_1" {
  count  = contains(local.final_regions_for_stacks, "me-riyadh-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.me-riyadh-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "me-riyadh-1"
  region_key        = local.subscribed_regions_map["me-riyadh-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "me-riyadh-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_mx_monterrey_1" {
  count  = contains(local.final_regions_for_stacks, "mx-monterrey-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.mx-monterrey-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "mx-monterrey-1"
  region_key        = local.subscribed_regions_map["mx-monterrey-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "mx-monterrey-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_mx_queretaro_1" {
  count  = contains(local.final_regions_for_stacks, "mx-queretaro-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.mx-queretaro-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "mx-queretaro-1"
  region_key        = local.subscribed_regions_map["mx-queretaro-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "mx-queretaro-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_sa_bogota_1" {
  count  = contains(local.final_regions_for_stacks, "sa-bogota-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.sa-bogota-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "sa-bogota-1"
  region_key        = local.subscribed_regions_map["sa-bogota-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "sa-bogota-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_sa_santiago_1" {
  count  = contains(local.final_regions_for_stacks, "sa-santiago-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.sa-santiago-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "sa-santiago-1"
  region_key        = local.subscribed_regions_map["sa-santiago-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "sa-santiago-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_sa_saopaulo_1" {
  count  = contains(local.final_regions_for_stacks, "sa-saopaulo-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.sa-saopaulo-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "sa-saopaulo-1"
  region_key        = local.subscribed_regions_map["sa-saopaulo-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "sa-saopaulo-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_sa_valparaiso_1" {
  count  = contains(local.final_regions_for_stacks, "sa-valparaiso-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.sa-valparaiso-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "sa-valparaiso-1"
  region_key        = local.subscribed_regions_map["sa-valparaiso-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "sa-valparaiso-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_sa_vinhedo_1" {
  count  = contains(local.final_regions_for_stacks, "sa-vinhedo-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.sa-vinhedo-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "sa-vinhedo-1"
  region_key        = local.subscribed_regions_map["sa-vinhedo-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "sa-vinhedo-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_uk_cardiff_1" {
  count  = contains(local.final_regions_for_stacks, "uk-cardiff-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.uk-cardiff-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "uk-cardiff-1"
  region_key        = local.subscribed_regions_map["uk-cardiff-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "uk-cardiff-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_uk_london_1" {
  count  = contains(local.final_regions_for_stacks, "uk-london-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.uk-london-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "uk-london-1"
  region_key        = local.subscribed_regions_map["uk-london-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "uk-london-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_us_ashburn_1" {
  count  = contains(local.final_regions_for_stacks, "us-ashburn-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.us-ashburn-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "us-ashburn-1"
  region_key        = local.subscribed_regions_map["us-ashburn-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "us-ashburn-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_us_chicago_1" {
  count  = contains(local.final_regions_for_stacks, "us-chicago-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.us-chicago-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "us-chicago-1"
  region_key        = local.subscribed_regions_map["us-chicago-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "us-chicago-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_us_phoenix_1" {
  count  = contains(local.final_regions_for_stacks, "us-phoenix-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.us-phoenix-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "us-phoenix-1"
  region_key        = local.subscribed_regions_map["us-phoenix-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "us-phoenix-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}

module "regional_deployment_us_sanjose_1" {
  count  = contains(local.final_regions_for_stacks, "us-sanjose-1") ? 1 : 0
  source = "./modules/regional-stacks"

  providers = {
    oci = oci.us-sanjose-1
  }

  tenancy_ocid      = var.tenancy_ocid
  region            = "us-sanjose-1"
  region_key        = local.subscribed_regions_map["us-sanjose-1"].region_key
  compartment_ocid  = module.compartment.id
  subnet_ocid       = lookup(local.region_to_subnet_ocid_map, "us-sanjose-1", "")
  datadog_site      = var.datadog_site
  api_key_secret_id = module.kms[0].api_key_secret_id
  home_region       = local.home_region_name
  tags              = local.tags

  depends_on = [
    terraform_data.prechecks_complete,
    module.compartment,
    module.auth,
    module.kms
  ]
}
