locals {
  metrics_image_path = "iad.ocir.io/iduhc9hzgn3o/sva-datadog-functions/metrics-forwarder:${var.metrics_image_tag}"
  logs_image_path    = "iad.ocir.io/iduhc9hzgn3o/sva-datadog-functions/logs-forwarder:${var.logs_image_tag}"

  config = merge(
    {
      "DD_COMPRESS"         = "true",
      "DD_SITE"             = var.datadog_site,
      "HOME_REGION"         = var.home_region,
      "API_KEY_SECRET_OCID" = var.api_key_secret_id
    },
    length(var.logs_image_tag) > 0 ? {
      "DATADOG_TAGS"  = "",
      "EXCLUDE"       = "{}",
      "DD_BATCH_SIZE" = "1000"
    } : {},
    length(var.metrics_image_tag) > 0 ? {
      "TENANCY_OCID"             = var.tenancy_id,
      "DETAILED_LOGGING_ENABLED" = "true"
    } : {}
  )
}
