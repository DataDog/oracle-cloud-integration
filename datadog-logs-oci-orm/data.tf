data "external" "logging_services" {
    program = ["bash", "logging_services.sh"]
}

# Step 1: Fetch all compartments in the tenancy
data "oci_identity_compartments" "all_compartments" {
  compartment_id = var.tenancy_ocid
  state = "ACTIVE"
}

# Step 2: Fetch all log groups in each compartment
data "oci_logging_log_groups" "log_groups_by_compartment" {
  for_each       = toset([for compartment in data.oci_identity_compartments.all_compartments.compartments : compartment.id])
  compartment_id = each.value
}

locals {
  flat_log_groups = flatten([
    for compartment_id, log_group_data in data.oci_logging_log_groups.log_groups_by_compartment : log_group_data.log_groups
  ])
}
# Step 3: Fetch all logs in each log group
data "oci_logging_logs" "logs_by_log_group" {
  for_each = toset([for log_group in local.flat_log_groups : log_group.id])
  log_group_id = each.value
}
