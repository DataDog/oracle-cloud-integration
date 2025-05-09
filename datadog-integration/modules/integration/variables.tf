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

variable "public_key_finger_print" {
  type        = string
  description = "The public key fingerptint of the service account user for authentication"
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
