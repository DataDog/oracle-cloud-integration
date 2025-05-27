#*************************************
#         TF auth Requirements
#*************************************

variable "compartment_name" {
  type        = string
  description = "Name of the compartment to create or use for Datadog resources. If a compartment with this name already exists, it will be used instead of creating a new one."
  default     = "Datadog"
}

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

variable "vcn_search_string" {
  type        = string
  description = "String to search for existing VCNs. If not provided, a new VCN will be created in each region."
  default     = null
}

variable "domain_name" {
  type        = string
  description = "If using an Identity Domain that is not Default, specify the domain name"
  default     = "Default"
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
