# Output the "list" of all subscribed regions.

output "all_availability_domains_in_your_tenancy" {
  value = data.oci_identity_region_subscriptions.subscriptions.region_subscriptions
}

output "vcn_network_details" {
  description = "Output of VCN Network Details"
  value = module.vcn.vcn_network_details
}

output "policy_details" {
  description = "Output of Log Forwarding Policy"
  value = module.policy.policy_details
}

output "function_app_details" {
  description = "Output of Function Application Details"
  value = module.functionapp.function_app_details
}


output "containerregistry_details" {
  description = "Output of Pushing Function image to Container registry"
  value = length(module.containerregistry) > 0 ? module.containerregistry[0].containerregistry_details : null
}

output "function_details" {
  description = "Output of function creation"
  value = module.function.function_details
}
