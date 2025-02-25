output "subnet_id" {
  value = module.vcn.subnet_id[local.subnet]
}
