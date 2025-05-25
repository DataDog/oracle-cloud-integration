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
  description = "The OCID of the existing user to create the API key for"
  type        = string
}

variable "domain_name" {
  description = "The name of the identity domain. If not provided, the default domain will be used."
  type        = string
  default     = "Default"
}

variable "auth_method" {
  description = "Authentication method for OCI CLI commands. Set to '--auth api_key' if running from the command line, leave blank if running from OCI Resource Manager."
  type        = string
  default     = ""
}
