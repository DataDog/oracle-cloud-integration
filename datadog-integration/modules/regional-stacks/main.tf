terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
  }
}

# Data source to find subnet by partial name when subnet_partial_name is provided
data "oci_core_subnets" "existing_subnet" {
  count = var.subnet_partial_name != "" ? 1 : 0
  
  compartment_id = var.compartment_ocid
  filter {
    name   = "display_name"
    values = [var.subnet_partial_name]
    regex  = true
  }
}

# Validation to ensure subnet is found when subnet_partial_name is provided
resource "null_resource" "validate_subnet" {
  count = var.subnet_partial_name != "" ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(data.oci_core_subnets.existing_subnet[0].subnets) > 0
      error_message = "No subnet found matching partial name '${var.subnet_partial_name}'"
    }
  }
}

resource "oci_functions_function" "logs_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-logs-forwarder"
  memory_in_mbs  = "1024"
  freeform_tags  = var.tags
  image          = local.logs_image_path
}

resource "oci_functions_function" "metrics_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-metrics-forwarder"
  memory_in_mbs  = "512"
  freeform_tags  = var.tags
  image          = local.metrics_image_path
}

module "vcn" {
  count  = var.subnet_partial_name == "" ? 1 : 0
  source = "oracle-terraform-modules/vcn/oci"
  version                  = "3.6.0"
  compartment_id           = var.compartment_ocid
  freeform_tags            = var.tags
  vcn_cidrs                = ["10.0.0.0/16"]
  vcn_dns_label            = "ddvcnmodule"
  vcn_name                 = local.vcn_name
  lockdown_default_seclist = false

  subnets = {
    private = {
      cidr_block = "10.0.0.0/16"
      type       = "private"
      name       = local.subnet
    }
  }

  create_nat_gateway           = true
  nat_gateway_display_name     = local.nat_gateway
  create_service_gateway       = true
  service_gateway_display_name = local.service_gateway
}

resource "oci_functions_application" "dd_function_app" {
  compartment_id = var.compartment_ocid
  display_name   = "dd-function-app"
  freeform_tags  = var.tags
  shape          = "GENERIC_X86_ARM"
  subnet_ids = [
    local.subnet_id
  ]
  config = local.config

  depends_on = [null_resource.validate_subnet]
}
