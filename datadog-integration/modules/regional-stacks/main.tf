terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
  }
}

resource "oci_functions_application" "dd_function_app" {
  compartment_id = var.compartment_ocid
  display_name   = "dd-function-app"
  freeform_tags  = var.tags
  shape          = "GENERIC_X86_ARM"
  subnet_ids = [
    module.vcn.subnet_id[local.subnet],
  ]
  config = local.config
}

resource "oci_functions_function" "logs_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-logs-forwarder"
  memory_in_mbs  = "1024"
  freeform_tags  = var.tags
  image          = local.logs_image_path
  image_digest   = local.image_sha_logs

}

resource "oci_functions_function" "metrics_function" {
  application_id = oci_functions_application.dd_function_app.id
  display_name   = "dd-metrics-forwarder"
  memory_in_mbs  = "512"
  freeform_tags  = var.tags
  image          = local.metrics_image_path
  image_digest   = local.image_sha_metrics
}

module "vcn" {
  source                   = "oracle-terraform-modules/vcn/oci"
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

