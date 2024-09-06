locals {
  # Names for the network infra
  vcn_name        = "${var.resource_name_prefix}-vcn"
  nat_gateway     = "${local.vcn_name}-natgateway"
  service_gateway = "${local.vcn_name}-servicegateway"
  subnet          = "${local.vcn_name}-private-subnet"
}

locals {
  # Names for the service connector
  connector_name = "${var.resource_name_prefix}-connector"
  connector_metric_namespaces = ["oci_autonomous_database", "oci_blockstore", "oci_compute_infrastructure_health", "oci_computeagent", "oci_computecontainerinstance", "oci_database", "oci_database_cluster", "oci_dynamic_routing_gateway", "oci_faas", "oci_fastconnect", "oci_filestorage", "oci_gpu_infrastructure_health", "oci_lbaas", "oci_mysql_database", "oci_nat_gateway", "oci_nlb", "oci_objectstorage", "oci_oke", "oci_queue", "oci_rdma_infrastructure_health", "oci_service_connector_hub", "oci_service_gateway", "oci_vcn", "oci_vpn", "oci_waf", "oracle_oci_database"]
}

locals {
  # Tags for the provisioned resource
  freeform_tags = {
    datadog-terraform = "true"
  }
}

locals {
  # Name for tenancy namespace, metadata and regions
  ocir_namespace = data.oci_objectstorage_namespace.namespace.namespace
  oci_regions = tomap({
    for reg in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions :
    reg.region_name => reg
  })
  oci_region_key      = lower(local.oci_regions[var.region].region_key)
  tenancy_home_region = data.oci_identity_tenancy.tenancy_metadata.home_region_key
}

locals {
  # OCI docker repository
  oci_docker_repository = "${local.oci_region_key}.ocir.io/${local.ocir_namespace}"
  oci_docker_host       = "${local.oci_region_key}.ocir.io"
  ocir_repo_name        = "${var.resource_name_prefix}-functions"
  function_name         = "datadog-function-metrics"
  docker_image_path     = "${local.oci_docker_repository}/${local.ocir_repo_name}/${local.function_name}:latest"
  custom_image_path     = var.function_image_path
  user_image_provided   = length(var.function_image_path) > 0 ? true : false
}
