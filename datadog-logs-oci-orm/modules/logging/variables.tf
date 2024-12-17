variable "exclude_services" {
  type        = list(string)
  description = "List of services to be excluded from logging"
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where logging resources exist"
}
