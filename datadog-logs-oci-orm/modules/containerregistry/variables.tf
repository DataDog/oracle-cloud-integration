variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "user_ocid" {
  type        = string
  description = "OCID of the user for managing docker images"
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where the container repository will be created"
}

variable "freeform_tags" {
  type        = map(string)
  description = "A map of freeform tags to apply to the resources"
  default     = {}
}

variable "resource_name_prefix" {
  type        = string
  description = "The prefix for the name of all of the resources"
}

variable "region" {
  type        = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
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
