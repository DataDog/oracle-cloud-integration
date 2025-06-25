variable "user_name" {
  description = "The name of the user to create. Only used if existing_user_id is not provided."
  type        = string
  default     = null
}

variable "user_email" {
  description = "The email address of the current user"
  type        = string
  default     = ""
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

variable "compartment_id" {
  type        = string
  description = "The OCID of the compartment for the dynamic group of all service connector resources"
}

variable "current_user_id" {
  description = "The OCID of the current user"
  type        = string
}

variable "idcs_endpoint" {
  description = "The IDCS endpoint URL for the domain"
  type        = string
}

variable "existing_user_id" {
  description = "The OCID of an existing user to use. If provided, user_name will be ignored."
  type        = string
  default     = null
}

variable "existing_group_id" {
  description = "The OCID of an existing group to use. If provided, a new group will not be created."
  type        = string
  default     = null
}

variable "user_group_name" {
  description = "The name of the user group to create"
  type        = string
  default     = null
}

variable "user_policy_name" {
  description = "The name of the user policy to create"
  type        = string
}

variable "dg_sch_name" {
  description = "The name of the dynamic group for service connector hubs"
  type        = string
}

variable "dg_fn_name" {
  description = "The name of the dynamic group for functions"
  type        = string
}

variable "dg_policy_name" {
  description = "The name of the dynamic group policy"
  type        = string
}

