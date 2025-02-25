variable "tenancy_id" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "region" {
  type = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
}

variable "compartment_id" {
  type        = string
  description = "The OCID of the compartment where the function app will be created"
}

variable "datadog_site" {
  type        = string
  description = "The Datadog site to send data to (e.g., datadoghq.com, datadoghq.eu)"
}

variable "tags" {
    description = "A map of tags to assign to the resource"
    type        = map(string)
    default     = {}
}

variable "subnet_id" {
  type        = string
  description = "The OCID of the subnet to be used for the function app"
}

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
