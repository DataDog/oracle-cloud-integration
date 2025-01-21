data "oci_objectstorage_namespace" "namespace" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_user" "docker_user" {
    #Required
    user_id = var.user_ocid
}
