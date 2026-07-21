terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
      # This module accepts an OCI provider configuration passed from the parent
      # to enable region-specific resource deployment
      configuration_aliases = [oci]
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

# Vault-count quota availability in this region, used to decide whether this
# region can have its own vault or must fall back to the home-region vault.
data "oci_limits_resource_availability" "vault_quota" {
  compartment_id = var.tenancy_ocid
  service_name   = "kms"
  limit_name     = "virtual-vault-count"
}

resource "oci_kms_vault" "datadog_vault" {
  count          = local.create_regional_vault ? 1 : 0
  compartment_id = var.compartment_ocid
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
  count      = local.create_regional_vault ? 1 : 0
  depends_on = [oci_kms_vault.datadog_vault]
  triggers   = { vault_id = oci_kms_vault.datadog_vault[0].id }
  provisioner "local-exec" {
    command = <<-EOT
      export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
      for i in $(seq 1 30); do
        RESULT=$(timeout 15 oci kms management key list \
          --endpoint "${oci_kms_vault.datadog_vault[0].management_endpoint}" \
          --compartment-id "${var.compartment_ocid}" 2>&1)
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
  count          = local.create_regional_vault ? 1 : 0
  compartment_id = var.compartment_ocid
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

resource "oci_vault_secret" "api_key" {
  count          = local.create_regional_vault ? 1 : 0
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.datadog_vault[0].id
  key_id         = oci_kms_key.datadog_key[0].id
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

resource "oci_functions_function" "logs_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-logs-forwarder"
  memory_in_mbs  = "1024"
  freeform_tags  = var.tags
  defined_tags   = var.defined_tags
  image          = local.logs_image_path
  image_digest   = length(local.image_sha_logs) > 0 ? local.image_sha_logs : null
}

resource "oci_functions_function" "metrics_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-metrics-forwarder"
  memory_in_mbs  = "512"
  freeform_tags  = var.tags
  defined_tags   = var.defined_tags
  image          = local.metrics_image_path
  image_digest   = length(local.image_sha_metrics) > 0 ? local.image_sha_metrics : null
}

module "vcn" {
  count                    = var.subnet_ocid == "" ? 1 : 0
  source                   = "oracle-terraform-modules/vcn/oci"
  version                  = "~> 3.6"
  compartment_id           = var.compartment_ocid
  freeform_tags            = var.tags
  defined_tags             = var.defined_tags
  vcn_cidrs                = ["10.0.0.0/16"]
  vcn_dns_label            = "ddvcnmodule"
  vcn_name                 = local.vcn_name
  lockdown_default_seclist = true
  subnets                  = {}

  create_nat_gateway           = true
  nat_gateway_display_name     = local.nat_gateway
  create_service_gateway       = true
  service_gateway_display_name = local.service_gateway
}

# Subnet submodule so we can pass defined_tags (upstream VCN module does not pass them to subnets).
module "subnet" {
  count          = var.subnet_ocid == "" ? 1 : 0
  source         = "oracle-terraform-modules/vcn/oci//modules/subnet"
  version        = "~> 3.6"
  compartment_id = var.compartment_ocid
  vcn_id         = module.vcn[0].vcn_id
  nat_route_id   = module.vcn[0].nat_route_id
  ig_route_id    = module.vcn[0].ig_route_id
  subnets = {
    private = {
      cidr_block = "10.0.0.0/16"
      type       = "private"
      name       = local.subnet
    }
  }
  freeform_tags = var.tags
  defined_tags  = var.defined_tags
}

resource "oci_core_default_security_list" "dd_default" {
  count                      = var.subnet_ocid == "" ? 1 : 0
  manage_default_resource_id = data.oci_core_vcn.dd_vcn[0].default_security_list_id
  depends_on                 = [module.vcn]
  freeform_tags              = var.tags

  egress_security_rules {
    destination      = "0.0.0.0/0"
    protocol         = "all"
    destination_type = "CIDR_BLOCK"
  }

  # ICMP type 3 code 4: path MTU discovery (from anywhere)
  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    icmp_options {
      type = 3
      code = 4
    }
  }

  # ICMP type 3: destination unreachable (from within VCN)
  ingress_security_rules {
    protocol    = "1"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    icmp_options {
      type = 3
    }
  }
}

resource "oci_functions_application" "dd_function_app" {
  compartment_id = var.compartment_ocid
  display_name   = "dd-function-app"
  freeform_tags  = var.tags
  defined_tags   = var.defined_tags
  shape          = "GENERIC_X86_ARM"
  subnet_ids = [
    local.subnet_id
  ]
  config = local.config
}
