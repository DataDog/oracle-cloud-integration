#
# Test harness for the datadog-terraform-onboarding module.
# Points at the local source so changes to ../datadog-terraform-onboarding are picked up
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
      version = "~> 7.1"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 1.20"
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
    "Client-ID"          = "terraform-test-datadog-onboarding"
  }
}

module "datadog_onboarding" {
  source = "../datadog-terraform-onboarding"

  tenancy_ocid      = var.tenancy_ocid
  current_user_ocid = var.current_user_ocid

  datadog_api_key = var.datadog_api_key
  datadog_app_key = var.datadog_app_key
  datadog_site    = var.datadog_site

  config_file_profile = var.config_file_profile

  # Optional advanced inputs — uncomment/override in terraform.tfvars as needed
  # resource_compartment_ocid     = var.resource_compartment_ocid
  # subnet_ocids                  = var.subnet_ocids
  # existing_user_id              = var.existing_user_id
  # existing_group_id             = var.existing_group_id
  # logs_enabled                  = var.logs_enabled
  # logs_only                     = var.logs_only
  # domain_id                     = var.domain_id
  # user_email                    = var.user_email
  # events_collection_enabled     = var.events_collection_enabled
  # defined_tags                  = var.defined_tags
  # enable_regional_vaults        = var.enable_regional_vaults
  # existing_home_region_vault_id = var.existing_home_region_vault_id
}
