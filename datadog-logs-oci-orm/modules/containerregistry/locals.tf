locals {
  # OCI docker repository
  registry_domain = "ocir.${var.region}.oci.oraclecloud.com"
  tenancy_namespace = data.oci_objectstorage_namespace.namespace.namespace
  function_name         = "datadog-function-logs"
  repo_name        = "${var.resource_name_prefix}-functions/${local.function_name}"
  docker_image_path     = "${local.registry_domain}/${local.tenancy_namespace}/${local.repo_name}"
  username = data.oci_identity_user.current_user.name
}
