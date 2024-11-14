resource "oci_sch_service_connector" "metrics_service_connector" {
  depends_on = [oci_functions_function.metrics_function]
  #Required
  compartment_id = var.compartment_ocid
  display_name   = local.connector_name
  source {
    #Required
    kind = "monitoring"

    #Optional
    monitoring_sources {

      #Optional
      compartment_id = var.compartment_ocid
      namespace_details {
        kind = "selected"
        dynamic "namespaces" {
          for_each = distinct(concat(local.connector_metric_namespaces, data.oci_monitoring_metrics.compartment_metrics.metrics[*].namespace))
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
