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
  description = "The OCID of the current user executing the terraform script"
}

#*************************************
#         Datadog Variables
#*************************************

variable "datadog_api_key" {
  type        = string
  description = "The API key for sending message to datadog endpoints"
  sensitive   = true
}

variable "datadog_app_key" {
  type        = string
  description = "The APP key for establishing integration with Datadog"
  sensitive   = true
}

variable "datadog_site" {
  type        = string
  description = "The Datadog site to send data to (e.g., datadoghq.com, datadoghq.eu)"
}

#*************************************
#         Advanced Usage Variables
#*************************************  

variable "subnet_ocids" {
  type        = string
  description = "Multiline string of subnet OCIDs (one per line) to use for the Datadog infrastructure. Each subnet OCID should be in the format: ocid1.subnet.oc[0-9].*"
  default     = ""
}

variable "compartment_id" {
  type        = string
  description = "OCID of the compartment to create or use for Datadog resources. If null, a compartment named 'Datadog' will be created in the tenancy."
  default     = null
}

variable "existing_user_id" {
  type        = string
  description = "The OCID of the existing user to use for DDOG authentication"
  default     = null
}

variable "existing_group_id" {
  type        = string
  description = "The OCID of the existing group to use for DDOG authentication"
  default     = null
}

variable "logs_enabled" {
  type        = bool
  description = "Indicates if logs should be enabled/disabled"
  default     = false
}
