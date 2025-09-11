terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
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

provider "restapi" {
  create_method = "POST"
  update_method = "PATCH"
  uri           = "https://api.${var.datadog_site}"
  headers = {
    "DD-API-KEY"         = var.datadog_api_key
    "DD-APPLICATION-KEY" = var.datadog_app_key
    "Content-Type"       = "application/json"
    "Client-ID"        = "oci-orm-stack"
  }
}
