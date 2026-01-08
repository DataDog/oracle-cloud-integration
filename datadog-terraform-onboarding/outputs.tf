output "regional_resources" {
  description = "Map of region to deployed resource OCIDs (function_app and subnet)"
  value = merge(
    length(module.regional_deployment_af_johannesburg_1) > 0 ? { "af-johannesburg-1" = module.regional_deployment_af_johannesburg_1[0].output_ids } : {},
    length(module.regional_deployment_ap_batam_1) > 0 ? { "ap-batam-1" = module.regional_deployment_ap_batam_1[0].output_ids } : {},
    length(module.regional_deployment_ap_chuncheon_1) > 0 ? { "ap-chuncheon-1" = module.regional_deployment_ap_chuncheon_1[0].output_ids } : {},
    length(module.regional_deployment_ap_hyderabad_1) > 0 ? { "ap-hyderabad-1" = module.regional_deployment_ap_hyderabad_1[0].output_ids } : {},
    length(module.regional_deployment_ap_melbourne_1) > 0 ? { "ap-melbourne-1" = module.regional_deployment_ap_melbourne_1[0].output_ids } : {},
    length(module.regional_deployment_ap_mumbai_1) > 0 ? { "ap-mumbai-1" = module.regional_deployment_ap_mumbai_1[0].output_ids } : {},
    length(module.regional_deployment_ap_osaka_1) > 0 ? { "ap-osaka-1" = module.regional_deployment_ap_osaka_1[0].output_ids } : {},
    length(module.regional_deployment_ap_seoul_1) > 0 ? { "ap-seoul-1" = module.regional_deployment_ap_seoul_1[0].output_ids } : {},
    length(module.regional_deployment_ap_singapore_1) > 0 ? { "ap-singapore-1" = module.regional_deployment_ap_singapore_1[0].output_ids } : {},
    length(module.regional_deployment_ap_singapore_2) > 0 ? { "ap-singapore-2" = module.regional_deployment_ap_singapore_2[0].output_ids } : {},
    length(module.regional_deployment_ap_sydney_1) > 0 ? { "ap-sydney-1" = module.regional_deployment_ap_sydney_1[0].output_ids } : {},
    length(module.regional_deployment_ap_tokyo_1) > 0 ? { "ap-tokyo-1" = module.regional_deployment_ap_tokyo_1[0].output_ids } : {},
    length(module.regional_deployment_ca_montreal_1) > 0 ? { "ca-montreal-1" = module.regional_deployment_ca_montreal_1[0].output_ids } : {},
    length(module.regional_deployment_ca_toronto_1) > 0 ? { "ca-toronto-1" = module.regional_deployment_ca_toronto_1[0].output_ids } : {},
    length(module.regional_deployment_eu_amsterdam_1) > 0 ? { "eu-amsterdam-1" = module.regional_deployment_eu_amsterdam_1[0].output_ids } : {},
    length(module.regional_deployment_eu_frankfurt_1) > 0 ? { "eu-frankfurt-1" = module.regional_deployment_eu_frankfurt_1[0].output_ids } : {},
    length(module.regional_deployment_eu_madrid_1) > 0 ? { "eu-madrid-1" = module.regional_deployment_eu_madrid_1[0].output_ids } : {},
    length(module.regional_deployment_eu_marseille_1) > 0 ? { "eu-marseille-1" = module.regional_deployment_eu_marseille_1[0].output_ids } : {},
    length(module.regional_deployment_eu_milan_1) > 0 ? { "eu-milan-1" = module.regional_deployment_eu_milan_1[0].output_ids } : {},
    length(module.regional_deployment_eu_paris_1) > 0 ? { "eu-paris-1" = module.regional_deployment_eu_paris_1[0].output_ids } : {},
    length(module.regional_deployment_eu_stockholm_1) > 0 ? { "eu-stockholm-1" = module.regional_deployment_eu_stockholm_1[0].output_ids } : {},
    length(module.regional_deployment_eu_zurich_1) > 0 ? { "eu-zurich-1" = module.regional_deployment_eu_zurich_1[0].output_ids } : {},
    length(module.regional_deployment_il_jerusalem_1) > 0 ? { "il-jerusalem-1" = module.regional_deployment_il_jerusalem_1[0].output_ids } : {},
    length(module.regional_deployment_me_abudhabi_1) > 0 ? { "me-abudhabi-1" = module.regional_deployment_me_abudhabi_1[0].output_ids } : {},
    length(module.regional_deployment_me_dubai_1) > 0 ? { "me-dubai-1" = module.regional_deployment_me_dubai_1[0].output_ids } : {},
    length(module.regional_deployment_me_jeddah_1) > 0 ? { "me-jeddah-1" = module.regional_deployment_me_jeddah_1[0].output_ids } : {},
    length(module.regional_deployment_me_riyadh_1) > 0 ? { "me-riyadh-1" = module.regional_deployment_me_riyadh_1[0].output_ids } : {},
    length(module.regional_deployment_mx_monterrey_1) > 0 ? { "mx-monterrey-1" = module.regional_deployment_mx_monterrey_1[0].output_ids } : {},
    length(module.regional_deployment_mx_queretaro_1) > 0 ? { "mx-queretaro-1" = module.regional_deployment_mx_queretaro_1[0].output_ids } : {},
    length(module.regional_deployment_sa_bogota_1) > 0 ? { "sa-bogota-1" = module.regional_deployment_sa_bogota_1[0].output_ids } : {},
    length(module.regional_deployment_sa_santiago_1) > 0 ? { "sa-santiago-1" = module.regional_deployment_sa_santiago_1[0].output_ids } : {},
    length(module.regional_deployment_sa_saopaulo_1) > 0 ? { "sa-saopaulo-1" = module.regional_deployment_sa_saopaulo_1[0].output_ids } : {},
    length(module.regional_deployment_sa_valparaiso_1) > 0 ? { "sa-valparaiso-1" = module.regional_deployment_sa_valparaiso_1[0].output_ids } : {},
    length(module.regional_deployment_sa_vinhedo_1) > 0 ? { "sa-vinhedo-1" = module.regional_deployment_sa_vinhedo_1[0].output_ids } : {},
    length(module.regional_deployment_uk_cardiff_1) > 0 ? { "uk-cardiff-1" = module.regional_deployment_uk_cardiff_1[0].output_ids } : {},
    length(module.regional_deployment_uk_london_1) > 0 ? { "uk-london-1" = module.regional_deployment_uk_london_1[0].output_ids } : {},
    length(module.regional_deployment_us_ashburn_1) > 0 ? { "us-ashburn-1" = module.regional_deployment_us_ashburn_1[0].output_ids } : {},
    length(module.regional_deployment_us_chicago_1) > 0 ? { "us-chicago-1" = module.regional_deployment_us_chicago_1[0].output_ids } : {},
    length(module.regional_deployment_us_phoenix_1) > 0 ? { "us-phoenix-1" = module.regional_deployment_us_phoenix_1[0].output_ids } : {},
    length(module.regional_deployment_us_sanjose_1) > 0 ? { "us-sanjose-1" = module.regional_deployment_us_sanjose_1[0].output_ids } : {},
    length(module.regional_deployment_eu_madrid_3) > 0 ? { "eu-madrid-3" = module.regional_deployment_eu_madrid_3[0].output_ids } : {},
    length(module.regional_deployment_eu_turin_1) > 0 ? { "eu-turin-1" = module.regional_deployment_eu_turin_1[0].output_ids } : {}
  )
}

output "compartment_id" {
  description = "OCID of the Datadog compartment"
  value       = module.compartment.id
}

output "api_key_secret_id" {
  description = "OCID of the API key secret in KMS"
  value       = module.kms.api_key_secret_id
}

output "datadog_user_ocid" {
  description = "OCID of the Datadog IAM user"
  value       = module.auth.user_id
}

output "datadog_integration_status" {
  description = "Status of Datadog integration registration"
  value       = module.integration.api_output
}
