variable "user_name" {
  description = "The name of the user"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "tenancy_id" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "compartment_name" {
  description = "The name of the compartment"
  type        = string
}

variable "compartment_id" {
  type        = string
  description = "The OCID of the compartment for the dynamic group of all service connector resources"
}

variable "current_user_id" {
  description = "The OCID of the current user"
  type        = string
}

