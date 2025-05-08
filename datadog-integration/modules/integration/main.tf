terraform {
  required_version = ">= 1.5.0"
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "2.0.1"
    }
  }
}

resource "restapi_object" "datadog_tenancy_integration" {
  path         = "/api/v2/integration/oci/tenancy"
  data         = local.request_data
  id_attribute = "data/id"
  read_path    = "/api/v2/integration/oci/tenancies/{id}"
}
