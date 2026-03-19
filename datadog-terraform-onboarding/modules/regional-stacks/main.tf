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
  version                  = ">= 3.6.0"
  compartment_id           = var.compartment_ocid
  freeform_tags            = var.tags
  defined_tags             = var.defined_tags
  vcn_cidrs                = ["10.0.0.0/16"]
  vcn_dns_label            = "ddvcnmodule"
  vcn_name                 = local.vcn_name
  lockdown_default_seclist  = true
  subnets                  = {}

  create_nat_gateway           = true
  nat_gateway_display_name     = local.nat_gateway
  create_service_gateway       = true
  service_gateway_display_name = local.service_gateway
}

# Subnet submodule so we can pass defined_tags (upstream VCN module does not pass them to subnets).
module "subnet" {
  count           = var.subnet_ocid == "" ? 1 : 0
  source          = "oracle-terraform-modules/vcn/oci//modules/subnet"
  version         = ">= 3.6.0"
  compartment_id  = var.compartment_ocid
  vcn_id          = module.vcn[0].vcn_id
  nat_route_id    = module.vcn[0].nat_route_id
  ig_route_id     = module.vcn[0].ig_route_id
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
