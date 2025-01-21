variable "group_id" {
  type        = string
  description = "Unique Name for the group of resource types"
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where resources exist"
}

variable "resource_types" {
  type        = list(string)
  description = "List of resource types"
}
