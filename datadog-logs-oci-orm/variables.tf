variable "resource_name_prefix" {
  type        = string
  description = "The prefix for the name of all of the resources"
  default     = "dd-logs"
}

#*************************************
#         VCN Variables
#*************************************
variable "create_vcn" {
  type        = bool
  default     = true
  description = "Optional variable to create virtual network for the setup. True by default"
}

variable "subnet_ocid" {
  type        = string
  default     = ""
  description = "The OCID of the subnet to be used for the function app. Required if not creating the VCN"
}

#*************************************
#         TF auth Requirements
#*************************************
variable "compartment_ocid" {
  type        = string
  description = "The compartment OCID to deploy resources to"
}
variable "region" {
  type        = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
}
variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}
