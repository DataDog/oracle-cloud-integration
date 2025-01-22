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
  }))
}
