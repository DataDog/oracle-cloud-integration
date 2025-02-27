variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "compartment_id" {
  type        = string
  description = "Compartment where terraform script is being executed"
}
