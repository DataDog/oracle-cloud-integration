variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "current_user_ocid" {
  type        = string
  description = "OCID of the logged in user running the terraform script"
}

variable "oci_region_key" {
  type        = string
  description = "The key of the OCI region where the resources will be deployed"
}

variable "auth_token_description" {
  description = "The description of the auth token to use for container registry login"
  type        = string
}

variable "auth_token" {
  type        = string
  description = "The user auth token for docker login to OCI container registry."
  sensitive   = true
}
