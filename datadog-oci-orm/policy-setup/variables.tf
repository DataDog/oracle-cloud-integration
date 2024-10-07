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

variable "dynamic_group_name" {
  type        = string
  description = "The name of the dynamic group for giving access to service connector"
  default     = "datadog-metrics-dynamic-group"
}

variable "user_group_name" {
  type        = string
  description = "The name of the group for giving access to user"
  default     = "DatadogAuthGroup"
}

variable "datadog_metrics_policy" {
  type        = string
  description = "The name of the policy for metrics"
  default     = "datadog-metrics-policy"
}

variable "user_domain" {
  type        = string
  description = "The name of the domain where the operation is to be run. It is assumed that the setup will create users and groups in the default domain. Enter the domain name if the user running the setup does not belong to Default domain."
  default     = "Default"
}


