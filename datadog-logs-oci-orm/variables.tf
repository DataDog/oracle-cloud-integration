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

#***************
#    Logging    
#***************
variable "exclude_services" {
  type        = list(string)
  default     = ["oacnativeproduction","apigateway","adm","apm","cloud_guard_query_results_prod","cloud_guard_raw_logs_prod","oke-k8s-cp-prod","contentdeliverynetwork","dataflow","dataintegration","datascience","delegateaccessprod","devops","emaildelivery","cloudevents","filestorage","goldengate","integration","loadbalancer","mediaflow","ocinetworkfirewall","postgresql","oci_c3_vpn","waa","waf","operatoraccessprod"]
  description = "List of services to be excluded from logging"
}

variable "logging_compartments_csv" {
  description = "Base64-encoded CSV file containing compartment IDs."
  default = "Y29tcGFydG1lbnRfaWQsbmFtZQoib2NpZDEuY29tcGFydG1lbnQub2MxLi5hYWFhYWFhYWRiNHBoZXhtZXVsNGpvc3Nwd2ZkYzJzZmdoN2ZnczZudHl3cW9xZWVxZjVsZmljNnBuNHEiLCJzdmEtdGVzdC1jb21wYXJ0bWVudCI="
  type        = string
}
