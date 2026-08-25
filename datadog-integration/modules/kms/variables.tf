variable "compartment_id" {
  type        = string
  description = "The OCID of the compartment where the vault will be created"
}

variable "tags" {
  type        = map(string)
  description = "A map of freeform tags to assign to resources"
  default     = {}
}

variable "defined_tags" {
  type        = map(string)
  description = "A map of defined tags to assign to resources"
  default     = {}
}

variable "datadog_api_key" {
  type        = string
  description = "The API key for sending message to datadog endpoints"
  sensitive   = true
}

variable "existing_vault_id" {
  type        = string
  description = "OCID of an existing datadog-vault to reuse instead of creating a new one. Set this when a prior vault is in PENDING_DELETION and vault quota is exhausted; the customer must cancel the deletion of the vault, the datadog-key, and the DatadogAPIKey secret so all three are usable. The existing DatadogAPIKey secret is reused as-is (its stored content is the API key the forwarder reads) — no new secret is created, because OCI holds a secret name for the full pending-deletion window. When non-null, the vault, key, and secret are read via data sources and never created."
  default     = null
}
