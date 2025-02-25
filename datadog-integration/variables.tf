#*************************************
#         TF auth Requirements
#*************************************
variable "compartment_ocid" {
  type = string
  description = "Compartment where terraform script is being executed"
}

variable "region" {
  type = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
}

variable "tenancy_ocid" {
  type = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}
variable "current_user_ocid" {
  type = string
  description = "The OCID of the current user executing the terraform script"
}

#*************************************
#         Datadog Variables
#*************************************
variable "datadog_api_key" {
  type = string
  description = "The API key for sending message to datadog endpoints"
  sensitive = true
}

variable "datadog_app_key" {
  type = string
  description = "The APP key for establishing integration with Datadog"
  sensitive = true
}

variable "datadog_site" {
  type        = string
  description = "The Datadog site to send data to (e.g., datadoghq.com, datadoghq.eu)"
}

#*************************************
#         Tenancy Options
#*************************************
variable "metrics_image_tag" {
  type = string
  description = "Image tag for forwarding metrics to Datadog"
  default = ""
}

variable "logs_image_tag" {
  type = string
  description = "Image tag for forwarding logs to Datadog"
  default = ""
}
