variable "resource_name_prefix" {
  type        = string
  description = "The prefix for the name of all of the resources"
  default     = "datadog-metrics"
}

variable "create_vcn" {
  type        = bool
  default     = true
  description = "Variable to create virtual network for the setup. True by default"
}

variable "datadog_api_key" {
  type        = string
  description = "The API key for sending message to datadog endpoints"
}

variable "function_subnet_id" {
  type        = string
  default     = ""
  description = "The OCID of the subnet to be used for the function app. If create_vcn is set to true, that will take precedence"
}

variable "function_app_shape" {
  type        = string
  default     = "GENERIC_ARM"
  description = "The shape of the function application. The docker image should be built accordingly. Use ARM if using Oracle Resource manager stack"
  validation {
    condition     = contains(["GENERIC_ARM", "GENERIC_X86", "GENERIC_X86_ARM"], var.function_app_shape)
    error_message = "Valid values are: GENERIC_ARM, GENERIC_X86, GENERIC_X86_ARM."
  }
}

variable "datadog_environment" {
  type        = string
  description = "The endpoint to hit for sending the metrics. Varies by different datacenter"
  validation {
    condition = contains(["ocimetrics-intake.datadoghq.com", "ocimetrics-intake.us5.datadoghq.com", "ocimetrics-intake.us3.datadoghq.com",
    "ocimetrics-intake.datadoghq.eu", "ocimetrics-intake.ap1.datadoghq.com", "ocimetrics-intake.ddog-gov.com", "ocimetrics-intake.datad0g.com"], var.datadog_environment)
    error_message = "Valid values for var: datadog_environment are (ocimetrics-intake.datadoghq.com, ocimetrics-intake.us5.datadoghq.com, ocimetrics-intake.us3.datadoghq.com, ocimetrics-intake.datadoghq.eu, ocimetrics-intake.ap1.datadoghq.com, ocimetrics-intake.ddog-gov.com)."
  }
}

variable "oci_docker_username" {
  type        = string
  sensitive   = true
  description = "The docker login username for the OCI container registry. Used in creating function image. Not required if the image is already exists."
}

variable "oci_docker_password" {
  type        = string
  sensitive   = true
  description = "The user auth token for the OCI docker container registry. Used in creating function image. Not required if the image already exists."
}

variable "service_connector_target_batch_size_in_kbs" {
  type        = string
  description = "The batch size (in Kb) in which to send payload to target"
  default     = "5000"
}

variable "metrics_namespaces" {
  type        = list(string)
  description = "The list of namespaces to collect the metrics for the metrics compartments. Remove any unwanted namespaces."
  default     = ["oci_autonomous_database", "oci_blockstore", "oci_compute_infrastructure_health", "oci_computeagent", "oci_computecontainerinstance", "oci_database", "oci_database_cluster", "oci_dynamic_routing_gateway", "oci_faas", "oci_fastconnect", "oci_filestorage", "oci_gpu_infrastructure_health", "oci_lbaas", "oci_mysql_database", "oci_nat_gateway", "oci_nlb", "oci_objectstorage", "oci_oke", "oci_queue", "oci_rdma_infrastructure_health", "oci_service_connector_hub", "oci_service_gateway", "oci_vcn", "oci_vpn", "oci_waf", "oracle_oci_database"]
}

variable "metrics_compartments" {
  type        = string
  description = "The comma separated list of compartments OCID to collect metrics."
}

#*************************************
#         TF auth Requirements
#*************************************
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
  description = "The compartment OCID to deploy resources to"
}
