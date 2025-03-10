terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

resource "oci_kms_vault" "datadog_vault" {
  compartment_id = var.compartment_id
  display_name   = "datadog-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = var.tags
}

resource "oci_kms_key" "datadog_key" {
  compartment_id = var.compartment_id
  display_name   = "datadog-key"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  management_endpoint = oci_kms_vault.datadog_vault.management_endpoint
  freeform_tags = var.tags
}

resource "oci_vault_secret" "api_key" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.datadog_vault.id
  key_id         = oci_kms_key.datadog_key.id
  secret_name    = "DatadogAPIKey"
  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.datadog_api_key)
  }
  freeform_tags = var.tags
}
