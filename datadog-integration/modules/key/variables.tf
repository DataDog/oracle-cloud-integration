#*************************************
#         TF auth Requirements
#*************************************

variable "compartment_ocid" {
  description = "The OCID of the compartment"
  type        = string
}

variable "region" {
  description = "The region to deploy to"
  type        = string
}

variable "tenancy_ocid" {
  description = "The OCID of the tenancy"
  type        = string
}

variable "existing_user_id" {
  description = "The OCID of the user for whom to create the API key"
  type        = string
}

variable "idcs_endpoint" {
  description = "The IDCS endpoint URL for the domain"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "auth_method" {
  description = "Authentication method for OCI CLI commands. Set to '--auth api_key' if running from the command line, leave blank if running from OCI Resource Manager."
  type        = string
  default     = ""
}
