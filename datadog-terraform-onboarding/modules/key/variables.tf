#*************************************
#         TF auth Requirements
#*************************************

variable "compartment_ocid" {
  description = "The OCID of the compartment"
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
