variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "region" {
  type        = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where the resources be created"
}

variable "datadog_site" {
  type        = string
  description = "The Datadog site to send data to (e.g., datadoghq.com, datadoghq.eu)"
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to the resource"
  default = {
    ownedby = "datadog"
  }
}

variable "home_region" {
  type        = string
  description = "The name of the home region, used as the vault region fallback when this region cannot create its own vault"
}

variable "api_key_secret_id" {
  type        = string
  description = "The secret ID of the home-region API key, used as a fallback when this region cannot create its own vault (e.g. vault quota exhausted)"
}

variable "datadog_api_key" {
  type        = string
  description = "The Datadog API key, seeded into this region's own vault secret"
  sensitive   = true
}

variable "create_regional_vault" {
  type        = bool
  description = "Whether this region has spare Vault quota to create its own vault; if false, falls back to the home-region vault"
}

variable "regional_vault_exists_in_state" {
  type        = string
  description = "\"true\" if this region's own vault already exists in state (computed by the caller); keeps create_regional_vault sticky so a later quota dip can't destroy an already-created vault"
  default     = "false"
}

variable "region_key" {
  type        = string
  description = "The 3 letter key of the region used."
}

variable "subnet_ocid" {
  type        = string
  description = "Optional OCID of an existing subnet to use. If not provided, a new subnet will be created."
  default     = ""

  validation {
    condition     = var.subnet_ocid == "" || can(regex("^ocid1\\.subnet\\.oc[0-9]\\.", var.subnet_ocid))
    error_message = "If provided, subnet_ocid must be a valid subnet OCID starting with: ocid1.subnet.oc[0-9]."
  }
}

variable "defined_tags" {
  type        = map(string)
  description = "Defined tags to assign to VCN, subnet, function app and functions."
  default     = {}
}
