# Output the "list" of all subscribed regions.

output "all_availability_domains_in_your_tenancy" {
  value = data.oci_identity_region_subscriptions.subscriptions.region_subscriptions
}

output "vcn_network_details" {
  description = "Output of VCN Network Details"
  value = module.vcn.vcn_network_details
}
