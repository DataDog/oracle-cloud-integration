locals {

  config_version = 2
  base_attributes = {
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
    dd_iac_version : trimspace(data.local_file.dd_iac_version.content)
    logs_config : {
      Enabled : var.logs_enabled
    }
    events_collection_enabled : var.events_collection_enabled
    defined_tags : [for k, v in var.defined_tags : "${k}:${v}"]
  }
  logs_only_attributes = { for k, v in {
    resource_collection_enabled : false
    metrics_config : {
      enabled : false
    }
  } : k => v if var.logs_only }
  json_object = {
    data : {
      type : "oci_tenancy",
      id : var.tenancy_ocid,
      attributes : merge(local.base_attributes, local.logs_only_attributes)
    }
  }
  request_data = jsonencode(local.json_object)
}
