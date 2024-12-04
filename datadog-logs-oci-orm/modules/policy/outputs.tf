output "policy_details" {
  description = "Output of creating policy for log forwarding"
  value       = {
    policy_name = oci_identity_policy.logs_policy.name
    policy_ocid = oci_identity_policy.logs_policy.id
    dynamic_group_name = oci_identity_dynamic_group.serviceconnector_group.name
    dynamic_group_ocid = oci_identity_dynamic_group.serviceconnector_group.id
  }
}
