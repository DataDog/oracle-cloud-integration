variable "compartment_id" {
  type        = string
  description = "The OCID of the compartment where the vault will be created"
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources"
  default     = {}
}

variable "datadog_api_key" {
  type        = string
  description = "The API key for sending message to datadog endpoints"
  sensitive   = true
}
