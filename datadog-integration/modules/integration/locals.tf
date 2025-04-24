locals {

  config_version = 2
  json_object = {
    data : {
      type : "oci_tenancy",
      id : var.tenancy_ocid,
      attributes : {
        home_region : var.home_region
        user_ocid : var.user_ocid
        config_version : local.config_version
        auth_credentials : {
          fingerprint : var.public_key_finger_print
          private_key : var.private_key
        }
      }
    }
  }
  request_data = jsonencode(local.json_object)
}
