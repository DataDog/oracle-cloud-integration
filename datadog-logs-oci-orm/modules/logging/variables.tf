variable "service_id" {
  type        = string
  description = "Logging Service Name"
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where logging resources exist"
}

variable "resource_types" {
  type = list(object({
      name       = string
      categories = list(object({
          name = string
      }))
  }))
  description = "List of resource types with their categories"
}
