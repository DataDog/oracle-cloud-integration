#*************************************
#         Variables for Datadog API
#*************************************

variable "datadog_api_key" {
  type        = string
  description = "The API key for identifying the Datadog org"
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

variable "private_key" {
  type        = string
  description = "The private key of the service account user for authentication"
}

variable "user_ocid" {
  type        = string
  description = "The OCID of the service account user created for authentication."
}

variable "home_region" {
  type        = string
  description = "The home region of the tenancy."
}

variable "tenancy_ocid" {
  type        = string
  description = "The OCID of the tenancy."
}

variable "subscribed_regions" {
  type        = list(string)
  description = "The list of subscribed regions"
}

variable "datadog_resource_compartment_id" {
  type        = string
  description = "The compartment id in which datadog resources are present."
}

variable "logs_enabled" {
  type        = bool
  description = "Indicates if logs should be enabled/disabled"
  default     = false
}

variable "metrics_enabled" {
  type        = bool
  description = "Indicates if metrics collection should be enabled/disabled"
  default     = true
}

variable "resources_enabled" {
  type        = bool
  description = "Indicates if resource collection should be enabled/disabled"
  default     = true
}

variable "cost_collection_enabled" {
  type        = bool
  description = "Indicates if cost collection should be enabled/disabled"
  default     = false
}

variable "enabled_regions" {
  type        = list(string)
  description = "List of OCI regions to enable for monitoring. If empty, all subscribed regions will be enabled by default."
  default     = []
}

variable "logs_enabled_services" {
  type        = list(string)
  description = "List of OCI log services to enable. If empty, Datadog's defaults will be used."
  default     = []
}

variable "logs_compartment_tag_filters" {
  type        = list(string)
  description = "List of compartment tag filters for log collection in Datadog tag format (key:value). Only logs from compartments with these tags will be collected. Maximum 100 tags. Example: [\"env:prod\", \"team:platform\"]"
  default     = []
}

variable "metrics_enabled_services" {
  type        = list(string)
  description = "List of OCI metric namespaces to enable. If empty, Datadog's defaults will be used."
  default     = []
}

variable "metrics_compartment_tag_filters" {
  type        = list(string)
  description = "List of compartment tag filters for metric collection in Datadog tag format (key:value). Only metrics from compartments with these tags will be collected. Maximum 100 tags. Example: [\"env:prod\", \"team:platform\"]"
  default     = []
}
