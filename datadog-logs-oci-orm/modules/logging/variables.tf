variable "freeform_tags" {
  type        = map(string)
  description = "A map of freeform tags to apply to the resources"
  default     = {}
}

variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where resources exist"
}

variable "service_map" {
  description = "A map of service names to a list of associated log categories."
  type = map(list(string))
}

variable "resources" {
  description = "A list of resource objects, each with compartmentId, displayName, groupId, identifier, and resourceType."
  type = list(object({
    compartmentId = string
    displayName   = string
    groupId       = string
    identifier    = string
    resourceType  = string
    timeCreated   = string
  }))
}

variable "enable_audit_log_forwarding" {
  type        = bool
  description = "Enable forwarding of audit logs to Datadog"
}
