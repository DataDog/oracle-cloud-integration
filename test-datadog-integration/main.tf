#
# Test harness for the datadog-integration (Resource Manager stack) module.
# Points at the local source so changes to ../datadog-integration are picked up
# without re-publishing. Fill in the placeholders in terraform.tfvars, then:
#
#   terraform init -backend=false
#   terraform plan
#

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.1"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "1.20.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

provider "oci" {
  region              = var.region
  config_file_profile = var.config_file_profile
}

provider "restapi" {
  create_method         = "POST"
  update_method         = "PATCH"
  uri                   = "https://api.${var.datadog_site}"
  create_returns_object = true
  headers = {
    "DD-API-KEY"         = var.datadog_api_key
    "DD-APPLICATION-KEY" = var.datadog_app_key
    "Content-Type"       = "application/json"
    "Client-ID"          = "terraform-test-datadog-integration"
  }
}

module "datadog_integration" {
  source = "../datadog-integration"

  tenancy_ocid      = var.tenancy_ocid
  region            = var.region
  current_user_ocid = var.current_user_ocid
  compartment_ocid  = var.compartment_ocid

  datadog_api_key = var.datadog_api_key
  datadog_app_key = var.datadog_app_key
  datadog_site    = var.datadog_site

  # Optional advanced inputs — uncomment/override in terraform.tfvars as needed
  # subnet_ocids                    = var.subnet_ocids
  # existing_user_id                = var.existing_user_id
  # existing_group_id               = var.existing_group_id
  # logs_enabled                    = var.logs_enabled
  # logs_only                       = var.logs_only
  # domain_id                       = var.domain_id
  # user_email                      = var.user_email
  # events_collection_enabled       = var.events_collection_enabled
  # defined_tags                    = var.defined_tags
  # apply_regional_stacks_sequentially = var.apply_regional_stacks_sequentially
  # enable_regional_vaults         = var.enable_regional_vaults
  # existing_home_region_vault_id   = var.existing_home_region_vault_id
}
