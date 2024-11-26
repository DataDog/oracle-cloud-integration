locals {
  # Names for the network infra
  vcn_name        = "${var.resource_name_prefix}-vcn"
  nat_gateway     = "${local.vcn_name}-natgateway"
  service_gateway = "${local.vcn_name}-servicegateway"
  subnet          = "${local.vcn_name}-private-subnet"
}
