variable "compartment_name" {
  description = "The name of the compartment"
  type        = string
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
