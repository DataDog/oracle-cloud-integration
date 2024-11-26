variable "create_vcn" {
  type        = bool
  description = "Optional variable to create virtual network for the setup. True by default"
}

variable "subnet_ocid" {
  type        = string
  description = "The OCID of the subnet to be used for the function app. Required if not creating the VCN"
}

#Module Arguments
variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where the resources will be created"
}

variable "resource_name_prefix" {
  type        = string
  description = "The prefix for the name of all of the resources"
  default     = "datadog-metrics"
}

variable "freeform_tags" {
  type        = map(string)
  description = "A map of freeform tags to apply to the resources"
  default     = {}
}
