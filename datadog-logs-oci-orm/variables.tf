variable "resource_name_prefix" {
  type        = string
  description = "The prefix for the name of all of the resources"
  default     = "dd-logs"
}

#*************************************
#         VCN Variables
#*************************************
variable "create_vcn" {
  type        = bool
  default     = true
  description = "Optional variable to create virtual network for the setup. True by default"
}

variable "vcn_compartment" {
  type        = string
  description = "The OCID of the compartment where networking resources are created"
}

variable "subnet_ocid" {
  type        = string
  default     = ""
  description = "The OCID of the subnet to be used for the function app. Required if not creating the VCN"
}

#*************************************
#         TF auth Requirements
#*************************************
variable "compartment_ocid" {
  type        = string
  description = "Compartment where terraform script is being executed"
}

variable "region" {
  type        = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
}

variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
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

#************************************
#    Function setup Variables    
#************************************
variable "function_app_shape" {
  type        = string
  default     = "GENERIC_ARM"
  description = "The shape of the function application. The docker image should be built accordingly."
  validation {
    condition     = contains(["GENERIC_ARM", "GENERIC_X86", "GENERIC_X86_ARM"], var.function_app_shape)
    error_message = "Valid values are: GENERIC_ARM, GENERIC_X86, GENERIC_X86_ARM."
  }
}

variable "oci_docker_username" {
  type        = string
  sensitive   = true
  description = "The docker login username for the OCI container registry. Used in creating function image."
}

variable "oci_docker_password" {
  type        = string
  sensitive   = true
  description = "The user auth token for the OCI docker container registry. Used in creating function image."
}

#***************
#    Logging    
#***************
variable "include_services" {
  type        = list(string)
  default     = []
  description = "List of services to be included in logging"
}

variable "logging_compartments" {
  type        = string
  description = "The comma separated list of compartments OCID to collect logs."
}

variable "enable_audit_log_forwarding" {
  type        = bool
  default     = false
  description = "Enable forwarding of audit logs to Datadog"
}
