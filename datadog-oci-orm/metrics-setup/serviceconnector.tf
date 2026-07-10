
# Local variables to manage connector hubs
locals {
  metrics_compartments        = local.is_service_user_available ? toset(split(",", var.metrics_compartments)) : toset([])
  metrics_compartments_sorted = sort(tolist(local.metrics_compartments))
  supported_namespaces        = var.metrics_namespaces
  # Fetch existing namespaces from the given compartments and intersect with those supported in var.metrics_namespaces
  compartment_tuple = [for comp in local.metrics_compartments_sorted : { compartment = comp, namespaces = tolist(setintersection(local.supported_namespaces, [for ns in data.oci_monitoring_metrics.existing_namespaces[comp].metrics : ns.namespace])) }]
  # Filter out the compartments having no namespaces to monitor. Each tuple having compartment id and list of namespaces.
  derived_namespaces = [for tup in local.compartment_tuple : tup if length(tup.namespaces) > 0]

  # Convert to json string.
  derived_namespaces_str = jsonencode(local.derived_namespaces)

  # Final balanced batches of compartments obtained from the script in data.external.connector_namespace_distribution.
  final_namespaces = jsondecode(data.external.connector_namespace_distribution.result.output)
}


# external script to balance the compartments and their namespaces. Returns a batch based on which connector hubs are created.
data "external" "connector_namespace_distribution" {
  program = ["python", "${path.module}/connector_namespaces.py", "${local.derived_namespaces_str}"]
}

resource "oci_sch_service_connector" "metrics_service_connector" {
  for_each   = { for i in range(0, length(local.final_namespaces)) : i => local.final_namespaces[i] }
  depends_on = [oci_functions_function.metrics_function]
  #Required
  compartment_id = var.compartment_ocid
  display_name   = "${local.connector_name}-${each.key}"
  source {
    #Required
    kind = "monitoring"

    #Optional
    dynamic "monitoring_sources" {
      for_each = each.value
      content {
        compartment_id = monitoring_sources.value.compartment
        namespace_details {
          kind = "selected"
          dynamic "namespaces" {
            for_each = monitoring_sources.value.namespaces
            content {
              metrics {
                #Required
                kind = "all"
              }
              namespace = namespaces.value
            }
          }
        }
      }
    }
  }
  target {
    #Required
    kind = "functions"

    #Optional
    batch_size_in_kbs = 4096
    batch_time_in_sec = 60
    compartment_id    = var.tenancy_ocid
    function_id       = oci_functions_function.metrics_function[0].id
  }

  #Optional
  defined_tags  = {}
  description   = "Terraform created connector hub to distribute metrics"
  freeform_tags = local.freeform_tags
}
