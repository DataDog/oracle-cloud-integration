data "oci_objectstorage_namespace" "namespace" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_user" "current_user" {
    #Required
    user_id = var.current_user_ocid
}
