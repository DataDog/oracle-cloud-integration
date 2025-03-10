locals {
  json_object = {
    data : {
      type : "CreateTenancyRequest"
      attributes : {
        tenancy_ocid : "${var.tenancy_ocid}",
        home_region : var.home_region
        user_ocid : var.user_ocid
        auth_credentials : {
          fingerprint : var.public_key_finger_print
          private_key : var.private_key
        }
      }
    }
  }
  request_data = jsonencode(local.json_object)
}
