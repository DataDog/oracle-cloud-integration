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

variable "custom_datadog_site" {
  type        = string
  description = "Optional custom intake host base (e.g. customerA.mrf.datadoghq.com). When set, forwarders send to https://{prefix-with-dashes}-{custom_datadog_site}{path} instead of the standard https://{prefix}.{datadog_site}{path}, keeping the host under a single wildcard certificate so no per-customer certificate is needed. Leave empty for the default dot-joined form."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "A map of freeform tags to assign to the resource"
  default = {
    ownedby = "datadog"
  }
}

variable "defined_tags" {
  type        = string
  description = "JSON-encoded map of defined tags (namespace.key = value), e.g. \"{\\\"Namespace.Key\\\":\\\"value\\\"}\". Passed from parent stack."
  default     = "{}"
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
    condition     = var.subnet_ocid == "" || can(regex("^ocid1\\.subnet\\.oc[0-9]\\.", var.subnet_ocid))
    error_message = "If provided, subnet_ocid must be a valid subnet OCID starting with: ocid1.subnet.oc[0-9]."
  }
}

variable "enable_regional_vaults" {
  type        = bool
  description = "Create a regional Vault, Key, and Secret in this region. When false the forwarder falls back to the home-region vault."
  default     = false
}

variable "image_namespace" {
  type        = string
  description = "OCIR object namespace hosting the Datadog forwarder images. Defaults to Datadog's commercial namespace (iddfxd5j9l2o); the parent stack overrides this with the realm-specific namespace for US Gov (OC2) and US DoD (OC3) tenancies."
  default     = "iddfxd5j9l2o"
}

variable "image_realm" {
  type        = string
  description = "OCI realm the images are pulled from. oc1 = commercial (<region-key>.ocir.io); oc2 = US Gov / oc3 = US DoD (ocir.<region>.oci.oraclegovcloud.com). Detected from the tenancy OCID prefix by the parent stack."
  default     = "oc1"

  validation {
    condition     = contains(["oc1", "oc2", "oc3"], var.image_realm)
    error_message = "image_realm must be one of: oc1, oc2, oc3."
  }
}
