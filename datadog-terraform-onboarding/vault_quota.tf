#
# Vault Quota Checks
#
# For each subscribed region, checks whether there is spare KMS virtual-vault
# quota to create a regional Datadog vault, and whether that region's vault
# already exists in state (so a later live-quota dip can't flip the decision
# back to false and destroy an already-created vault -- the vault itself
# consumes one unit of the quota it was created under). Must live in the
# root module (not nested inside modules/regional-stacks) because the
# regional-stacks module calls carry a module-level depends_on
# (module.compartment, module.auth), which propagates a deferred/unknown
# status onto everything nested inside the module -- including data sources
# with no direct reference to those dependencies -- making their attributes
# unusable in a count expression.
#

data "oci_limits_resource_availability" "vault_quota_af_johannesburg_1" {
  count          = contains(local.final_regions_for_stacks, "af-johannesburg-1") ? 1 : 0
  provider       = oci.af-johannesburg-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_af_johannesburg_1" {
  count = contains(local.final_regions_for_stacks, "af-johannesburg-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_af_johannesburg_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_batam_1" {
  count          = contains(local.final_regions_for_stacks, "ap-batam-1") ? 1 : 0
  provider       = oci.ap-batam-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_batam_1" {
  count = contains(local.final_regions_for_stacks, "ap-batam-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_batam_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_chuncheon_1" {
  count          = contains(local.final_regions_for_stacks, "ap-chuncheon-1") ? 1 : 0
  provider       = oci.ap-chuncheon-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_chuncheon_1" {
  count = contains(local.final_regions_for_stacks, "ap-chuncheon-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_chuncheon_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_hyderabad_1" {
  count          = contains(local.final_regions_for_stacks, "ap-hyderabad-1") ? 1 : 0
  provider       = oci.ap-hyderabad-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_hyderabad_1" {
  count = contains(local.final_regions_for_stacks, "ap-hyderabad-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_hyderabad_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_melbourne_1" {
  count          = contains(local.final_regions_for_stacks, "ap-melbourne-1") ? 1 : 0
  provider       = oci.ap-melbourne-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_melbourne_1" {
  count = contains(local.final_regions_for_stacks, "ap-melbourne-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_melbourne_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_mumbai_1" {
  count          = contains(local.final_regions_for_stacks, "ap-mumbai-1") ? 1 : 0
  provider       = oci.ap-mumbai-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_mumbai_1" {
  count = contains(local.final_regions_for_stacks, "ap-mumbai-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_mumbai_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_osaka_1" {
  count          = contains(local.final_regions_for_stacks, "ap-osaka-1") ? 1 : 0
  provider       = oci.ap-osaka-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_osaka_1" {
  count = contains(local.final_regions_for_stacks, "ap-osaka-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_osaka_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_seoul_1" {
  count          = contains(local.final_regions_for_stacks, "ap-seoul-1") ? 1 : 0
  provider       = oci.ap-seoul-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_seoul_1" {
  count = contains(local.final_regions_for_stacks, "ap-seoul-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_seoul_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_singapore_1" {
  count          = contains(local.final_regions_for_stacks, "ap-singapore-1") ? 1 : 0
  provider       = oci.ap-singapore-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_singapore_1" {
  count = contains(local.final_regions_for_stacks, "ap-singapore-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_singapore_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_singapore_2" {
  count          = contains(local.final_regions_for_stacks, "ap-singapore-2") ? 1 : 0
  provider       = oci.ap-singapore-2
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_singapore_2" {
  count = contains(local.final_regions_for_stacks, "ap-singapore-2") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_singapore_2(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_sydney_1" {
  count          = contains(local.final_regions_for_stacks, "ap-sydney-1") ? 1 : 0
  provider       = oci.ap-sydney-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_sydney_1" {
  count = contains(local.final_regions_for_stacks, "ap-sydney-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_sydney_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ap_tokyo_1" {
  count          = contains(local.final_regions_for_stacks, "ap-tokyo-1") ? 1 : 0
  provider       = oci.ap-tokyo-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ap_tokyo_1" {
  count = contains(local.final_regions_for_stacks, "ap-tokyo-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ap_tokyo_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ca_montreal_1" {
  count          = contains(local.final_regions_for_stacks, "ca-montreal-1") ? 1 : 0
  provider       = oci.ca-montreal-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ca_montreal_1" {
  count = contains(local.final_regions_for_stacks, "ca-montreal-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ca_montreal_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_ca_toronto_1" {
  count          = contains(local.final_regions_for_stacks, "ca-toronto-1") ? 1 : 0
  provider       = oci.ca-toronto-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_ca_toronto_1" {
  count = contains(local.final_regions_for_stacks, "ca-toronto-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_ca_toronto_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_amsterdam_1" {
  count          = contains(local.final_regions_for_stacks, "eu-amsterdam-1") ? 1 : 0
  provider       = oci.eu-amsterdam-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_amsterdam_1" {
  count = contains(local.final_regions_for_stacks, "eu-amsterdam-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_amsterdam_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_frankfurt_1" {
  count          = contains(local.final_regions_for_stacks, "eu-frankfurt-1") ? 1 : 0
  provider       = oci.eu-frankfurt-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_frankfurt_1" {
  count = contains(local.final_regions_for_stacks, "eu-frankfurt-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_frankfurt_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_madrid_1" {
  count          = contains(local.final_regions_for_stacks, "eu-madrid-1") ? 1 : 0
  provider       = oci.eu-madrid-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_madrid_1" {
  count = contains(local.final_regions_for_stacks, "eu-madrid-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_madrid_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_marseille_1" {
  count          = contains(local.final_regions_for_stacks, "eu-marseille-1") ? 1 : 0
  provider       = oci.eu-marseille-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_marseille_1" {
  count = contains(local.final_regions_for_stacks, "eu-marseille-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_marseille_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_milan_1" {
  count          = contains(local.final_regions_for_stacks, "eu-milan-1") ? 1 : 0
  provider       = oci.eu-milan-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_milan_1" {
  count = contains(local.final_regions_for_stacks, "eu-milan-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_milan_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_paris_1" {
  count          = contains(local.final_regions_for_stacks, "eu-paris-1") ? 1 : 0
  provider       = oci.eu-paris-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_paris_1" {
  count = contains(local.final_regions_for_stacks, "eu-paris-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_paris_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_stockholm_1" {
  count          = contains(local.final_regions_for_stacks, "eu-stockholm-1") ? 1 : 0
  provider       = oci.eu-stockholm-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_stockholm_1" {
  count = contains(local.final_regions_for_stacks, "eu-stockholm-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_stockholm_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_zurich_1" {
  count          = contains(local.final_regions_for_stacks, "eu-zurich-1") ? 1 : 0
  provider       = oci.eu-zurich-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_zurich_1" {
  count = contains(local.final_regions_for_stacks, "eu-zurich-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_zurich_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_il_jerusalem_1" {
  count          = contains(local.final_regions_for_stacks, "il-jerusalem-1") ? 1 : 0
  provider       = oci.il-jerusalem-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_il_jerusalem_1" {
  count = contains(local.final_regions_for_stacks, "il-jerusalem-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_il_jerusalem_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_me_abudhabi_1" {
  count          = contains(local.final_regions_for_stacks, "me-abudhabi-1") ? 1 : 0
  provider       = oci.me-abudhabi-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_me_abudhabi_1" {
  count = contains(local.final_regions_for_stacks, "me-abudhabi-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_me_abudhabi_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_me_dubai_1" {
  count          = contains(local.final_regions_for_stacks, "me-dubai-1") ? 1 : 0
  provider       = oci.me-dubai-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_me_dubai_1" {
  count = contains(local.final_regions_for_stacks, "me-dubai-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_me_dubai_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_me_jeddah_1" {
  count          = contains(local.final_regions_for_stacks, "me-jeddah-1") ? 1 : 0
  provider       = oci.me-jeddah-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_me_jeddah_1" {
  count = contains(local.final_regions_for_stacks, "me-jeddah-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_me_jeddah_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_me_riyadh_1" {
  count          = contains(local.final_regions_for_stacks, "me-riyadh-1") ? 1 : 0
  provider       = oci.me-riyadh-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_me_riyadh_1" {
  count = contains(local.final_regions_for_stacks, "me-riyadh-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_me_riyadh_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_mx_monterrey_1" {
  count          = contains(local.final_regions_for_stacks, "mx-monterrey-1") ? 1 : 0
  provider       = oci.mx-monterrey-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_mx_monterrey_1" {
  count = contains(local.final_regions_for_stacks, "mx-monterrey-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_mx_monterrey_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_mx_queretaro_1" {
  count          = contains(local.final_regions_for_stacks, "mx-queretaro-1") ? 1 : 0
  provider       = oci.mx-queretaro-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_mx_queretaro_1" {
  count = contains(local.final_regions_for_stacks, "mx-queretaro-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_mx_queretaro_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_sa_bogota_1" {
  count          = contains(local.final_regions_for_stacks, "sa-bogota-1") ? 1 : 0
  provider       = oci.sa-bogota-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_sa_bogota_1" {
  count = contains(local.final_regions_for_stacks, "sa-bogota-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_sa_bogota_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_sa_santiago_1" {
  count          = contains(local.final_regions_for_stacks, "sa-santiago-1") ? 1 : 0
  provider       = oci.sa-santiago-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_sa_santiago_1" {
  count = contains(local.final_regions_for_stacks, "sa-santiago-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_sa_santiago_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_sa_saopaulo_1" {
  count          = contains(local.final_regions_for_stacks, "sa-saopaulo-1") ? 1 : 0
  provider       = oci.sa-saopaulo-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_sa_saopaulo_1" {
  count = contains(local.final_regions_for_stacks, "sa-saopaulo-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_sa_saopaulo_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_sa_valparaiso_1" {
  count          = contains(local.final_regions_for_stacks, "sa-valparaiso-1") ? 1 : 0
  provider       = oci.sa-valparaiso-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_sa_valparaiso_1" {
  count = contains(local.final_regions_for_stacks, "sa-valparaiso-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_sa_valparaiso_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_sa_vinhedo_1" {
  count          = contains(local.final_regions_for_stacks, "sa-vinhedo-1") ? 1 : 0
  provider       = oci.sa-vinhedo-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_sa_vinhedo_1" {
  count = contains(local.final_regions_for_stacks, "sa-vinhedo-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_sa_vinhedo_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_uk_cardiff_1" {
  count          = contains(local.final_regions_for_stacks, "uk-cardiff-1") ? 1 : 0
  provider       = oci.uk-cardiff-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_uk_cardiff_1" {
  count = contains(local.final_regions_for_stacks, "uk-cardiff-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_uk_cardiff_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_uk_london_1" {
  count          = contains(local.final_regions_for_stacks, "uk-london-1") ? 1 : 0
  provider       = oci.uk-london-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_uk_london_1" {
  count = contains(local.final_regions_for_stacks, "uk-london-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_uk_london_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_us_ashburn_1" {
  count          = contains(local.final_regions_for_stacks, "us-ashburn-1") ? 1 : 0
  provider       = oci.us-ashburn-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_us_ashburn_1" {
  count = contains(local.final_regions_for_stacks, "us-ashburn-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_us_ashburn_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_us_chicago_1" {
  count          = contains(local.final_regions_for_stacks, "us-chicago-1") ? 1 : 0
  provider       = oci.us-chicago-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_us_chicago_1" {
  count = contains(local.final_regions_for_stacks, "us-chicago-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_us_chicago_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_us_phoenix_1" {
  count          = contains(local.final_regions_for_stacks, "us-phoenix-1") ? 1 : 0
  provider       = oci.us-phoenix-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_us_phoenix_1" {
  count = contains(local.final_regions_for_stacks, "us-phoenix-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_us_phoenix_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_us_sanjose_1" {
  count          = contains(local.final_regions_for_stacks, "us-sanjose-1") ? 1 : 0
  provider       = oci.us-sanjose-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_us_sanjose_1" {
  count = contains(local.final_regions_for_stacks, "us-sanjose-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_us_sanjose_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_madrid_3" {
  count          = contains(local.final_regions_for_stacks, "eu-madrid-3") ? 1 : 0
  provider       = oci.eu-madrid-3
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_madrid_3" {
  count = contains(local.final_regions_for_stacks, "eu-madrid-3") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_madrid_3(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "oci_limits_resource_availability" "vault_quota_eu_turin_1" {
  count          = contains(local.final_regions_for_stacks, "eu-turin-1") ? 1 : 0
  provider       = oci.eu-turin-1
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

data "external" "vault_state_eu_turin_1" {
  count = contains(local.final_regions_for_stacks, "eu-turin-1") ? 1 : 0
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_eu_turin_1(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}
