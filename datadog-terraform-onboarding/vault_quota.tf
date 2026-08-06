#
# Vault Quota and State Checks
#
# Two for_each data sources replace the previous 42 × 2 static per-region blocks:
#
#   vault_state — runs for every subscribed region on every apply (cheap: reads
#                 only local Terraform state). Not gated on enable_regional_vaults
#                 so the stickiness check still protects existing vaults even
#                 when the flag is toggled off.
#
#   vault_quota — runs only for regions where (a) enable_regional_vaults is true,
#                 (b) the region is not the home region (which already has a vault
#                 from module.kms), AND (c) the vault does not yet exist in state.
#                 Regions with an existing vault skip the OCI API call entirely;
#                 stickiness in the module keeps them regardless of live quota.
#
# Must remain in the root module — a module-level depends_on (module.compartment,
# module.auth) defers data source attributes, making them unusable in count/for_each
# expressions inside the module.
#

data "external" "vault_state" {
  for_each = toset(local.final_regions_for_stacks)
  program = ["bash", "-c", <<-EOT
    STATE=$(terraform state list 2>/dev/null)
    VAULT_EXISTS="false"
    echo "$STATE" | grep -qE '^module\.regional_deployment_${replace(each.key, "-", "_")}(\[[0-9]+\])?\.oci_kms_vault\.datadog_vault' && VAULT_EXISTS="true"
    echo "{\"vault_exists\": \"$VAULT_EXISTS\"}"
  EOT
  ]
}

data "external" "vault_quota" {
  for_each = var.enable_regional_vaults ? {
    for region in local.final_regions_for_stacks :
    region => region
    if region != local.home_region_name && data.external.vault_state[region].result.vault_exists != "true"
  } : {}

  program = ["bash", "-c", <<-EOT
    available=$(oci limits resource-availability get \
      --service-name kms \
      --limit-name virtual-vault-count \
      --region "${each.key}" \
      --compartment-id "${var.tenancy_ocid}" \
      --query 'data.available' \
      --raw-output 2>/dev/null || echo "0")
    echo "{\"available\": \"$${available:-0}\"}"
  EOT
  ]
}
