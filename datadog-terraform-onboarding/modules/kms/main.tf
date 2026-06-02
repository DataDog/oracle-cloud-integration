terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}


resource "oci_kms_vault" "datadog_vault" {
  compartment_id = var.compartment_id
  display_name   = "datadog-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = var.tags
  defined_tags   = var.defined_tags

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# Workaround for OCI provider race condition: vault DNS endpoint is not immediately
# resolvable after creation, causing key creation to fail.
resource "null_resource" "wait_for_vault_dns" {
  depends_on = [oci_kms_vault.datadog_vault]
  triggers   = { vault_id = oci_kms_vault.datadog_vault.id }

  provisioner "local-exec" {
    command = <<-EOT
      export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
      for i in $(seq 1 30); do
        RESULT=$(timeout 15 oci kms management key list \
          --endpoint "${oci_kms_vault.datadog_vault.management_endpoint}" \
          --compartment-id "${var.compartment_id}" 2>&1)
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ] || echo "$RESULT" | grep -q "ServiceError"; then exit 0; fi
        echo "Attempt $i: vault endpoint not yet reachable, retrying in 10s..."
        sleep 10
      done
      echo "ERROR: Vault endpoint did not become reachable after 300s. Re-apply the stack to retry."
      exit 1
    EOT
  }
}

resource "oci_kms_key" "datadog_key" {
  compartment_id = var.compartment_id
  display_name   = "datadog-key"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  management_endpoint = oci_kms_vault.datadog_vault.management_endpoint
  freeform_tags       = var.tags
  defined_tags        = var.defined_tags
  depends_on          = [null_resource.wait_for_vault_dns]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
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
  defined_tags  = var.defined_tags

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

