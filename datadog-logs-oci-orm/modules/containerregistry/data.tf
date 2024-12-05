data "oci_objectstorage_namespace" "namespace" {
  compartment_id = var.tenancy_ocid
}
