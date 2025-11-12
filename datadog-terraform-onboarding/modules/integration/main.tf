terraform {
  required_version = ">= 1.5.0"
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = ">= 1.20.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0.0"
    }
  }
}

resource "restapi_object" "datadog_tenancy_integration" {
  path         = "/api/v2/integration/oci/tenancies"
  data         = local.request_data
  id_attribute = "data/id"
  read_path    = "/api/v2/integration/oci/tenancies/{id}"
}
