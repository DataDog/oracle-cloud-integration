terraform {
  required_version = ">= 1.5.0"
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "1.20.0"
    }
  }
}

resource "restapi_object" "datadog_tenancy_integration" {
  path         = "/api/v2/integration/oci/tenancy"
  data         = local.request_data
  id_attribute = "data/attributes/tenancy_ocid"
  read_path    = "/api/v2/integration/oci/tenancies/{id}"
}
