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

locals {
  # When the customer reuses an existing vault (e.g. a prior datadog-vault is in
  # PENDING_DELETION and vault quota is exhausted), we read the vault, its key,
  # AND the API-key secret via data sources instead of creating them. The secret
  # is reused as-is — we do NOT create a new one — because OCI holds a secret
  # name for the entire pending-deletion window (~30 days), so a fresh secret
  # of the same name would be rejected as a duplicate. Reusing the existing
  # ACTIVE secret avoids that collision. The customer must cancel the deletion
  # of the vault, the key, AND the secret so all three are usable.
  reuse_vault = var.existing_home_region_vault_id != null && var.existing_home_region_vault_id != ""
}

# Reuse path: read the existing vault by OCID.
data "oci_kms_vault" "existing" {
  count    = local.reuse_vault ? 1 : 0
  vault_id = var.existing_home_region_vault_id
}

# Reuse path: find the existing datadog-key inside the reused vault. The key is
# looked up by display name on the vault's management endpoint. We scope the
# lookup to the compartment the reused vault actually lives in (read from the
# vault data source) rather than var.compartment_id, so the Terraform layer
# matches the precheck's validate_existing_vault (which derives the compartment
# from the vault itself). In the documented flow both compartments coincide —
# the OCID points at a vault in the Datadog compartment this stack manages —
# but deriving it from the vault keeps the two layers consistent even if a
# customer points existing_home_region_vault_id at a vault in another compartment.
data "oci_kms_keys" "existing" {
  count               = local.reuse_vault ? 1 : 0
  compartment_id      = data.oci_kms_vault.existing[0].compartment_id
  management_endpoint = data.oci_kms_vault.existing[0].management_endpoint
}

# Reuse path: find the existing DatadogAPIKey secret in the vault. We reuse the
# ACTIVE one as-is; the validation provisioner below enforces that one exists.
# compartment_id is taken from the reused vault for the same reason as
# oci_kms_keys.existing above.
data "oci_vault_secrets" "existing" {
  count          = local.reuse_vault ? 1 : 0
  compartment_id = data.oci_kms_vault.existing[0].compartment_id
  vault_id       = data.oci_kms_vault.existing[0].id
  name           = "DatadogAPIKey"
}

locals {
  # Resolve the vault OCID from whichever path is active.
  vault_id = local.reuse_vault ? data.oci_kms_vault.existing[0].id : oci_kms_vault.datadog_vault[0].id
  # The reused key's OCID is the first key named datadog-key in the vault that
  # is ENABLED. try() keeps an empty filtered list from throwing at plan time;
  # the apply-time validation provisioner surfaces a clear message instead.
  existing_key_id = local.reuse_vault ? try(
    [for k in data.oci_kms_keys.existing[0].keys : k.id if k.display_name == "datadog-key" && k.state == "ENABLED"][0],
    null
  ) : null
  key_id = local.reuse_vault ? local.existing_key_id : oci_kms_key.datadog_key[0].id
  # The reused secret's OCID is the first DatadogAPIKey secret in the vault
  # that is ACTIVE. try() guards the [0] index the same way as existing_key_id.
  existing_secret_id = local.reuse_vault ? try(
    [for s in data.oci_vault_secrets.existing[0].secrets : s.id if s.state == "ACTIVE"][0],
    null
  ) : null
}

# Validate that the reused vault is usable before we rely on it: the vault must
# be ACTIVE, named datadog-vault, contain an ENABLED datadog-key, AND contain an
# ACTIVE DatadogAPIKey secret. Fails the apply early with a clear message
# instead of a downstream index-out-of-bounds or a failed forwarder.
resource "null_resource" "existing_vault_validation" {
  count = local.reuse_vault ? 1 : 0

  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command    = <<-EOT
      VAULT_STATE='${data.oci_kms_vault.existing[0].state}'
      VAULT_NAME='${data.oci_kms_vault.existing[0].display_name}'
      if [ "$VAULT_STATE" != "ACTIVE" ]; then
        echo "ERROR: existing_home_region_vault_id '${var.existing_home_region_vault_id}' is in state '$VAULT_STATE', not ACTIVE."
        echo "Cancel the deletion of the existing datadog-vault to restore it to ACTIVE, then re-apply."
        exit 1
      fi
      if [ "$VAULT_NAME" != "datadog-vault" ]; then
        echo "ERROR: existing_home_region_vault_id '${var.existing_home_region_vault_id}' is named '$VAULT_NAME', not 'datadog-vault'."
        echo "existing_home_region_vault_id must point at a vault created by a previous Datadog install."
        exit 1
      fi
      KEY_ID='${local.existing_key_id}'
      if [ -z "$KEY_ID" ] || [ "$KEY_ID" = "null" ]; then
        echo "ERROR: existing_home_region_vault_id '${var.existing_home_region_vault_id}' was reused, but no ENABLED key named 'datadog-key' was found inside it."
        echo "Either cancel the deletion of the existing datadog-key, or unset existing_home_region_vault_id to create a fresh vault."
        exit 1
      fi
      SECRET_ID='${local.existing_secret_id}'
      if [ -z "$SECRET_ID" ] || [ "$SECRET_ID" = "null" ]; then
        echo "ERROR: existing_home_region_vault_id '${var.existing_home_region_vault_id}' was reused, but no ACTIVE secret named 'DatadogAPIKey' was found inside it."
        echo "Cancel the deletion of the existing DatadogAPIKey secret to restore it to ACTIVE, then re-apply."
        echo "The existing secret is reused as-is (its stored content is the API key the forwarder reads)."
        exit 1
      fi
      echo "✅ Reusing existing vault ${var.existing_home_region_vault_id}, datadog-key $KEY_ID, and DatadogAPIKey secret $SECRET_ID"
    EOT
  }
}

# Create path: only when not reusing.
resource "oci_kms_vault" "datadog_vault" {
  count          = local.reuse_vault ? 0 : 1
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
  count      = local.reuse_vault ? 0 : 1
  depends_on = [oci_kms_vault.datadog_vault]
  triggers   = { vault_id = oci_kms_vault.datadog_vault[0].id }

  provisioner "local-exec" {
    command = <<-EOT
      export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
      for i in $(seq 1 30); do
        RESULT=$(timeout 15 oci kms management key list \
          --endpoint "${oci_kms_vault.datadog_vault[0].management_endpoint}" \
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
  count          = local.reuse_vault ? 0 : 1
  compartment_id = var.compartment_id
  display_name   = "datadog-key"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  management_endpoint = oci_kms_vault.datadog_vault[0].management_endpoint
  freeform_tags       = var.tags
  defined_tags        = var.defined_tags
  depends_on          = [null_resource.wait_for_vault_dns]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# The secret is created ONLY on the create path (fresh vault). On the reuse
# path the existing ACTIVE DatadogAPIKey secret is reused as-is — we do not
# create a new one, because OCI holds the secret name for the full pending-
# deletion window and a duplicate would be rejected. The reused secret's stored
# content is the API key the forwarder reads; the datadog_api_key variable is
# only written on the create path. To rotate the API key on a reused vault, the
# customer must update the secret content out-of-band or unset
# existing_home_region_vault_id to recreate the vault stack.
resource "oci_vault_secret" "api_key" {
  count          = local.reuse_vault ? 0 : 1
  compartment_id = var.compartment_id
  vault_id       = local.vault_id
  key_id         = local.key_id
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
