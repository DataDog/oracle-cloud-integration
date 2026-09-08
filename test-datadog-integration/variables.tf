#
# Variable declarations for the datadog-integration test harness.
#

variable "tenancy_ocid" {
  type    = string
  default = null
}

variable "region" {
  type    = string
  default = null
}

variable "current_user_ocid" {
  type    = string
  default = null
}

variable "compartment_ocid" {
  type    = string
  default = null
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "datadog_app_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "datadog_site" {
  type    = string
  default = "datadoghq.com"
}

variable "config_file_profile" {
  type    = string
  default = "DEFAULT"
}

# --- Optional advanced inputs (match datadog-integration/variables.tf) ---
variable "subnet_ocids" {
  type    = string
  default = ""
}

variable "existing_user_id" {
  type    = string
  default = null
}

variable "existing_group_id" {
  type    = string
  default = null
}

variable "logs_enabled" {
  type    = bool
  default = true
}

variable "logs_only" {
  type    = bool
  default = false
}

variable "domain_id" {
  type    = string
  default = null
}

variable "user_email" {
  type    = string
  default = null
}

variable "events_collection_enabled" {
  type    = bool
  default = false
}

variable "defined_tags" {
  type    = string
  default = ""
}

variable "apply_regional_stacks_sequentially" {
  type    = bool
  default = false
}

variable "enable_regional_vaults" {
  type    = bool
  default = false
}

variable "existing_home_region_vault_id" {
  type    = string
  default = null
}
