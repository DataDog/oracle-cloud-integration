locals {

  config_version = 3
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
          enabled : length(var.enabled_regions) > 0 ? var.enabled_regions : var.subscribed_regions
        }
        dd_compartment_id : var.datadog_resource_compartment_id
        dd_stack_id : try(data.external.stack_info.result.stack_id, "")
        logs_config : {
          Enabled = var.logs_enabled
          enabled_services = var.logs_enabled_services
          compartment_tag_filters = var.logs_compartment_tag_filters
        }
        metrics_config : {
          enabled = var.metrics_enabled
          enabled_services = var.metrics_enabled_services
          compartment_tag_filters = var.metrics_compartment_tag_filters
        }
        resource_collection_enabled : var.resources_enabled
        cost_collection_enabled : var.cost_collection_enabled
      }
    }
  }
  request_data = jsonencode(local.json_object)
}
