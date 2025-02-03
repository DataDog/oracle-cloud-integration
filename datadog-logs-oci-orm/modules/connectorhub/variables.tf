variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where resources exist"
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

variable "function_ocid" {
  description = "OCID of the function to which logs will be sent"
  type        = string
}

variable "audit_log_compartments" {
  description = "List of audit log compartments"
  type = list(string)
}

variable "service_log_groups" {
  description = "A list of maps where each map contains details about an audit log group, including the log group ID and the compartment ID where it is located."
  type = list(object({
    log_group_id = string
    compartment_id     = string
  }))
}
