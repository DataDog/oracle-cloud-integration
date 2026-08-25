#*************************************
#         TF auth Requirements
#*************************************

# DEPLOYMENT COMPARTMENT: Where Datadog resources (vault, functions, VCNs) will be deployed.
# If null, a new compartment named 'Datadog' will be created under the tenancy root.
# If set, uses that existing compartment for all Datadog resources.
variable "resource_compartment_ocid" {
  type        = string
  description = "OCID of the compartment to create or use for Datadog resources. If null, a compartment named 'Datadog' will be created in the tenancy."
  default     = null
}

variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "current_user_ocid" {
  type        = string
  description = "The OCID of the current user executing the terraform script"
}

#*************************************
#         Datadog Variables
#*************************************

variable "datadog_api_key" {
  type        = string
  description = "The API key for sending message to datadog endpoints"
  sensitive   = true
}

variable "datadog_app_key" {
  type        = string
  description = "The APP key for establishing integration with Datadog"
  sensitive   = true
}

variable "datadog_site" {
  type        = string
  description = "The Datadog site to send data to (e.g., datadoghq.com, datadoghq.eu)"
}

#*************************************
#         Advanced Usage Variables
#*************************************

variable "subnet_ocids" {
  type        = string
  description = "Multiline string of subnet OCIDs (one per line) to use for the Datadog infrastructure. Each subnet OCID should be in the format: ocid1.subnet.oc[0-9].*"
  default     = ""
}

variable "existing_user_id" {
  type        = string
  description = "The OCID of the existing user to use for DDOG authentication"
  default     = null
}

variable "existing_group_id" {
  type        = string
  description = "The OCID of the existing group to use for DDOG authentication"
  default     = null
}

variable "logs_enabled" {
  type        = bool
  description = "Indicates if logs should be enabled/disabled"
  default     = true
}

variable "logs_only" {
  type        = bool
  description = "Indicates if the integration should be created with metric and resource collection disabled, but available"
  default     = false
}

variable "domain_id" {
  type        = string
  description = "The OCID of the Identity Domain to use for the Datadog QuickStart stack"
  default     = null
}

variable "user_email" {
  type        = string
  description = "Email address where you want OCI to send you notifications about the created user."
  default     = null
}

variable "events_collection_enabled" {
  type        = bool
  description = "Indicates if event collection (OCI Events Service) should be enabled"
  default     = false
}

variable "defined_tags" {
  type        = string
  description = "Defined tags to apply to all created resources. One entry per line in the format namespace.key:value (e.g. CostCenter.Environment:prod). Leave blank unless your tenancy has mandatory tag defaults."
  default     = ""
}

variable "config_file_profile" {
  type        = string
  description = "Oracle CLI config file profile name to be used for provider configurations."
  default     = "DEFAULT"
}

variable "enable_regional_vaults" {
  type        = bool
  description = "Create a regional Vault, Key, and Secret in each subscribed region so that region's forwarder reads its API key locally instead of crossing to the home region. Existing customers must explicitly set this to true to opt in; the default is false to preserve prior behavior."
  default     = false
}

variable "existing_home_region_vault_id" {
  type        = string
  description = <<-EOT
    OCID of an existing datadog-vault in the home region to reuse instead of creating a new one. This is a home-region-only escape hatch for the case where a prior install's home-region vault is in PENDING_DELETION and the tenancy has no spare virtual-vault-count quota to create another. Set it only when you are hitting that quota error and want to re-use the previous datadog-vault's key and secret.

    Prerequisites the customer must perform first:
      1. Cancel the deletion of the existing datadog-vault (restores it to ACTIVE).
      2. Cancel the deletion of the datadog-key inside that vault (also a 7-day window).
      3. Cancel the deletion of the DatadogAPIKey secret inside that vault (restores it to ACTIVE).

    The existing DatadogAPIKey secret is reused as-is — its stored content is the API key the forwarder reads. We do NOT create a new secret, because OCI holds a secret name for the full pending-deletion window and a duplicate would be rejected. When this is set, the vault-quota precondition in prechecks.tf is skipped (the apply does not create a vault).

    Only the home-region vault (module.kms) is reused via this variable. Regional vaults (modules/regional-stacks) are unaffected and still fall back to the home-region vault — the reused one when this is set — when their own quota is exhausted.
  EOT
  default     = null
}
