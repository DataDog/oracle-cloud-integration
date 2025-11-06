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

variable "enable_vault" {
  type        = bool
  default     = false
  description = "Enable KMS Vault creation for storing API keys. Set to false for testing to avoid OCI vault limits (10 vaults, 7+ day deletion period). When false, functions will deploy but won't work until a vault is configured."
}

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
  default     = true
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
  description = "List of OCI regions to enable for monitoring. If empty, all subscribed regions will be enabled by default. Example: [\"us-ashburn-1\", \"eu-frankfurt-1\"]"
  default     = []
}

variable "logs_enabled_services" {
  type        = list(string)
  description = "List of OCI log services to enable. If empty, Datadog's defaults will be used."
  default     = []
  
  validation {
    condition = alltrue([
      for service in var.logs_enabled_services : contains([
        "audit", "adm", "adbd", "dataintegration", "functions", "integration",
        "ocinetworkfirewall", "objectstorage", "operatoraccessprod", "postgresql",
        "cloud_guard_raw_logs_prod", "contentdeliverynetwork", "mediaflow", "goldengate",
        "oacnativeproduction", "oke-k8s-cp-prod", "dataflow", "cloudevents", "filestorage",
        "oci-cache", "oci_c3_vpn", "adi", "och", "emaildelivery", "flowlogs", "workengine",
        "cloud_guard_query_results_prod", "loadbalancer", "devops", "keymanagementservice",
        "waa", "apigateway", "apm", "datascience", "delegateaccessprod", "waf"
      ], service)
    ])
    error_message = "Invalid log service specified. Please use only services from the allowed list."
  }
}

variable "logs_compartment_tag_filters" {
  type        = list(string)
  description = "List of compartment tag filters for log collection in Datadog tag format (key:value). Only logs from compartments with these tags will be collected. Maximum 100 tags. Example: [\"env:prod\", \"team:platform\"]"
  default     = []
  
  validation {
    condition = alltrue([
      for tag in var.logs_compartment_tag_filters : can(regex("^!?[^:,]+(:[^:,]+)?(,!?[^:,]+(:[^:,]+)?)*$", tag))
    ])
    error_message = "Tags must be in Datadog format: 'key' or 'key:value', comma-separated, with optional '!' negation (e.g., 'env:prod', '!env:staging,!testing')."
  }
  
  validation {
    condition     = length(var.logs_compartment_tag_filters) <= 100
    error_message = "Maximum of 100 compartment tag filters allowed."
  }
}

variable "metrics_enabled_services" {
  type        = list(string)
  description = "List of OCI metric namespaces to enable. If empty, Datadog's defaults will be used."
  default     = []
  
  validation {
    condition = alltrue([
      for service in var.metrics_enabled_services : contains([
        "oci_compute", "oci_block_storage", "oci_file_storage", "oci_object_storage",
        "oci_autonomous_database", "oci_database", "oci_mysql_database", "oci_postgresql",
        "oci_load_balancer", "oci_network_firewall", "oci_nat_gateway", "oci_internet_gateway",
        "oci_service_gateway", "oci_dynamic_routing_gateway", "oci_vcn", "oci_vpn", "oci_fastconnect",
        "oci_functions", "oci_api_gateway", "oci_service_connector_hub", "oci_integration",
        "oci_oke", "oci_container_instances", "oci_instancepools", "oci_cloudevents",
        "oci_servicemesh", "oci_visual_builder", "oci_goldengate", "oci_mediastreams",
        "oci_waf", "oci_queue", "oci_ebs", "oracle_appmgmt"
      ], service)
    ])
    error_message = "Invalid metric namespace specified. Please use only namespaces from the allowed list."
  }
}

variable "metrics_compartment_tag_filters" {
  type        = list(string)
  description = "List of compartment tag filters for metric collection in Datadog tag format (key:value). Only metrics from compartments with these tags will be collected. Maximum 100 tags. Example: [\"env:prod\", \"team:platform\"]"
  default     = []
  
  validation {
    condition = alltrue([
      for tag in var.metrics_compartment_tag_filters : can(regex("^!?[^:,]+(:[^:,]+)?(,!?[^:,]+(:[^:,]+)?)*$", tag))
    ])
    error_message = "Tags must be in Datadog format: 'key' or 'key:value', comma-separated, with optional '!' negation (e.g., 'env:prod', '!env:staging,!testing')."
  }
  
  validation {
    condition     = length(var.metrics_compartment_tag_filters) <= 100
    error_message = "Maximum of 100 compartment tag filters allowed."
  }
}

variable "domain_id" {
  type        = string
  description = "The OCID of the Identity Domain to use for the Datadog QuickStart stack"
  default     = null
}

variable "user_email" {
  type        = string
  description = "Email address where you want OCI to send you notifications about the created user."
  default     = null
}
