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
          private_key : var.private_key
        },
        regions_config : {
          available : var.subscribed_regions
        }
        dd_compartment_id : var.datadog_resource_compartment_id
        dd_stack_id : try(data.external.stack_info.result.stack_id, "")
      }
    }
  }
  request_data = jsonencode(local.json_object)
}
