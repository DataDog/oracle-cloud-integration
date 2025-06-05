variable "compartment_id" {
  description = "The id of the compartment"
  type        = string
  default     = null
}

variable "parent_compartment_id" {
  description = "The ID of the parent compartment"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the compartment"
  type        = map(string)
  default     = {}
}

variable "new_compartment_name" {
  description = "The name of the new compartment to create, if no compartment_id is provided"
  type        = string
  default     = "Datadog"
}