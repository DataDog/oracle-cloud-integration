locals {
  # OCI docker repository
  ocir_namespace = data.oci_objectstorage_namespace.namespace.namespace
  oci_docker_host       = "${var.oci_region_key}.ocir.io"
  oci_docker_repository = "${local.oci_docker_host}/${local.ocir_namespace}"
  username = data.oci_identity_user.docker_user.name
}
