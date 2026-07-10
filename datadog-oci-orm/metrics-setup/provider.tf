terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

provider "oci" {
  tenancy_ocid        = var.tenancy_ocid
  region              = var.region
  config_file_profile = var.config_file_profile
}

provider "oci" {
  alias               = "home"
  tenancy_ocid        = var.tenancy_ocid
  region              = local.tenancy_home_region
  config_file_profile = var.config_file_profile
}
