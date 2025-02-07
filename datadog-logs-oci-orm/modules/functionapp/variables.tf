variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where the function app will be created"
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

#************************************
#   Function Application Variables   
#************************************
variable "subnet_ocid" {
  type        = string
  description = "The OCID of the subnet to be used for the function app"
}

#*************************************
#         Datadog Variables
#*************************************
variable "datadog_api_key" {
  type        = string
  description = "The API key for sending message to datadog endpoints"
}

variable "datadog_endpoint" {
  type        = string
  description = "The endpoint to hit for sending the logs."
  validation {
    condition = contains(["http-intake.logs.datadoghq.com", "http-intake.logs.us5.datadoghq.com", "http-intake.logs.us3.datadoghq.com",
    "http-intake.logs.datadoghq.eu", "http-intake.logs.ap1.datadoghq.com"], var.datadog_endpoint)
    error_message = "Valid values for var: datadog_endpoint are (http-intake.logs.datadoghq.com, http-intake.logs.us5.datadoghq.com, http-intake.logs.us3.datadoghq.com, http-intake.logs.datadoghq.eu, http-intake.logs.ap1.datadoghq.com)."
  }
}

variable "datadog_tags" {
  type        = string
  default     = ""
  description = "The tags to be sent with the logs. The tags should be in the format key1:value1,key2:value2"
}
