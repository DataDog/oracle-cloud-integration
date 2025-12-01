variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "region" {
  type        = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where the resources be created"
}

variable "datadog_site" {
  type        = string
  description = "The Datadog site to send data to (e.g., datadoghq.com, datadoghq.eu)"
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to the resource"
  default = {
    ownedby = "datadog"
  }
}

variable "home_region" {
  type        = string
  description = "The name of the home region"
}

variable "api_key_secret_id" {
  type        = string
  description = "The secret ID for the API key"
}

variable "region_key" {
  type        = string
  description = "The 3 letter key of the region used."
}

variable "subnet_ocid" {
  type        = string
  description = "Optional OCID of an existing subnet to use. If not provided, a new subnet will be created."
  default     = ""
  
  validation {
    condition = var.subnet_ocid == "" || can(regex("^ocid1\\.subnet\\.oc[0-9]\\.", var.subnet_ocid))
    error_message = "If provided, subnet_ocid must be a valid subnet OCID starting with: ocid1.subnet.oc[0-9]."
  }
}
