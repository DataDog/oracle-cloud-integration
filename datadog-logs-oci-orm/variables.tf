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

variable "current_user_ocid" {
  type        = string
  description = "OCID of the logged in user running the terraform script"
}

#************************************
#   Function Application Variables   
#************************************
variable "function_app_shape" {
  type        = string
  default     = "GENERIC_ARM"
  description = "The shape of the function application. The docker image should be built accordingly. Use ARM if using Oracle Resource manager stack"
  validation {
    condition     = contains(["GENERIC_ARM", "GENERIC_X86", "GENERIC_X86_ARM"], var.function_app_shape)
    error_message = "Valid values are: GENERIC_ARM, GENERIC_X86, GENERIC_X86_ARM."
  }
}

variable "function_image_path" {
  type        = string
  default     = ""
  description = "The full path of the function image. The image should be present in the container registry for the region"
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
    condition     = contains(["http-intake.logs.datadoghq.com"], var.datadog_endpoint)
    error_message = "Valid values for var: datadog_endpoint are (http-intake.logs.datadoghq.com)."
  }
}

variable "datadog_tags" {
  type        = string
  default     = ""
  description = "The tags to be sent with the logs. The tags should be in the format key1:value1,key2:value2"
}

#************************************
#    Container Registry Variables    
#************************************
variable "auth_token_description" {
  description = "The description of the auth token to use for container registry login"
  type        = string
  default     = "datadog-auth-token"
}

variable "auth_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "The user auth token for docker login to OCI container registry."
}

variable "service_user_ocid" {
  type        = string
  default     = ""
  description = "The OCID of the service user to be used for Docker login and pushing images."
}

#***************
#    Logging    
#***************
variable "exclude_services" {
  type        = list(string)
  default     = []
  description = "List of services to be excluded from logging"
}

variable "logging_compartments_csv" {
  description = "Base64-encoded CSV file containing compartment IDs."
  default = "Y29tcGFydG1lbnRfaWQsbmFtZQoib2NpZDEuY29tcGFydG1lbnQub2MxLi5hYWFhYWFhYWRiNHBoZXhtZXVsNGpvc3Nwd2ZkYzJzZmdoN2ZnczZudHl3cW9xZWVxZjVsZmljNnBuNHEiLCJzdmEtdGVzdC1jb21wYXJ0bWVudCI="
  type        = string
}
