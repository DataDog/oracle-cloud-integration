locals {
  # Variables to manage connector hubs
  metrics_compartments    = toset(split(",", var.metrics_compartments))
  supported_namespaces    = var.metrics_namespaces
  compartment_tuple       = [for comp in local.metrics_compartments : { compartment = comp, namespaces = tolist(setintersection(local.supported_namespaces, [for ns in data.oci_monitoring_metrics.existing_namespaces[comp].metrics : ns.namespace])) }]
  # Order by compartment id
  temp_derived_namespaces = { for tup in local.compartment_tuple : tup.compartment => tup.namespaces if length(tup.namespaces) > 0 }
  
  # Filter out the comaprtments having no namespaces to monitor
  derived_namespaces      = [for key, value in local.temp_derived_namespaces : { compartment = key, namespaces = value }]
  max_namespaces          = 15
  # Having large number of compartments
  single_compartments   = chunklist([for tup in local.derived_namespaces : tup if length(tup.namespaces) > local.max_namespaces], 1)
  mumtiple_compartments = chunklist([for val in local.derived_namespaces : { compartment = val.compartment, namespaces = val.namespaces } if length(val.namespaces) > 0 && length(val.namespaces) <= local.max_namespaces], 5)
  final_namespaces      = concat(local.single_compartments, local.mumtiple_compartments)
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
    batch_size_in_kbs = var.service_connector_target_batch_size_in_kbs
    batch_time_in_sec = 60
    compartment_id    = var.tenancy_ocid
    function_id       = oci_functions_function.metrics_function.id
  }

  #Optional
  defined_tags  = {}
  description   = "Terraform created connector hub to distribute metrics"
  freeform_tags = local.freeform_tags
}
