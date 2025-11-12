terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = ">= 1.20.0"
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
    "Client-ID"        = "terraform-advanced-onboarding"
  }
}

#*************************************
#   OCI Provider Aliases (Multi-Region)
#*************************************
# These provider aliases enable multi-region deployment in a single Terraform stack.
# Only regions that are subscribed will actually be deployed (count = 0 for others).
# Generated from: oci iam region list (2025-10-22)

provider "oci" {
  alias  = "af-johannesburg-1"
  region = "af-johannesburg-1"
}

provider "oci" {
  alias  = "ap-batam-1"
  region = "ap-batam-1"
}

provider "oci" {
  alias  = "ap-chuncheon-1"
  region = "ap-chuncheon-1"
}

provider "oci" {
  alias  = "ap-hyderabad-1"
  region = "ap-hyderabad-1"
}

provider "oci" {
  alias  = "ap-melbourne-1"
  region = "ap-melbourne-1"
}

provider "oci" {
  alias  = "ap-mumbai-1"
  region = "ap-mumbai-1"
}

provider "oci" {
  alias  = "ap-osaka-1"
  region = "ap-osaka-1"
}

provider "oci" {
  alias  = "ap-seoul-1"
  region = "ap-seoul-1"
}

provider "oci" {
  alias  = "ap-singapore-1"
  region = "ap-singapore-1"
}

provider "oci" {
  alias  = "ap-singapore-2"
  region = "ap-singapore-2"
}

provider "oci" {
  alias  = "ap-sydney-1"
  region = "ap-sydney-1"
}

provider "oci" {
  alias  = "ap-tokyo-1"
  region = "ap-tokyo-1"
}

provider "oci" {
  alias  = "ca-montreal-1"
  region = "ca-montreal-1"
}

provider "oci" {
  alias  = "ca-toronto-1"
  region = "ca-toronto-1"
}

provider "oci" {
  alias  = "eu-amsterdam-1"
  region = "eu-amsterdam-1"
}

provider "oci" {
  alias  = "eu-frankfurt-1"
  region = "eu-frankfurt-1"
}

provider "oci" {
  alias  = "eu-madrid-1"
  region = "eu-madrid-1"
}

provider "oci" {
  alias  = "eu-marseille-1"
  region = "eu-marseille-1"
}

provider "oci" {
  alias  = "eu-milan-1"
  region = "eu-milan-1"
}

provider "oci" {
  alias  = "eu-paris-1"
  region = "eu-paris-1"
}

provider "oci" {
  alias  = "eu-stockholm-1"
  region = "eu-stockholm-1"
}

provider "oci" {
  alias  = "eu-zurich-1"
  region = "eu-zurich-1"
}

provider "oci" {
  alias  = "il-jerusalem-1"
  region = "il-jerusalem-1"
}

provider "oci" {
  alias  = "me-abudhabi-1"
  region = "me-abudhabi-1"
}

provider "oci" {
  alias  = "me-dubai-1"
  region = "me-dubai-1"
}

provider "oci" {
  alias  = "me-jeddah-1"
  region = "me-jeddah-1"
}

provider "oci" {
  alias  = "me-riyadh-1"
  region = "me-riyadh-1"
}

provider "oci" {
  alias  = "mx-monterrey-1"
  region = "mx-monterrey-1"
}

provider "oci" {
  alias  = "mx-queretaro-1"
  region = "mx-queretaro-1"
}

provider "oci" {
  alias  = "sa-bogota-1"
  region = "sa-bogota-1"
}

provider "oci" {
  alias  = "sa-santiago-1"
  region = "sa-santiago-1"
}

provider "oci" {
  alias  = "sa-saopaulo-1"
  region = "sa-saopaulo-1"
}

provider "oci" {
  alias  = "sa-valparaiso-1"
  region = "sa-valparaiso-1"
}

provider "oci" {
  alias  = "sa-vinhedo-1"
  region = "sa-vinhedo-1"
}

provider "oci" {
  alias  = "uk-cardiff-1"
  region = "uk-cardiff-1"
}

provider "oci" {
  alias  = "uk-london-1"
  region = "uk-london-1"
}

provider "oci" {
  alias  = "us-ashburn-1"
  region = "us-ashburn-1"
}

provider "oci" {
  alias  = "us-chicago-1"
  region = "us-chicago-1"
}

provider "oci" {
  alias  = "us-phoenix-1"
  region = "us-phoenix-1"
}

provider "oci" {
  alias  = "us-sanjose-1"
  region = "us-sanjose-1"
}
