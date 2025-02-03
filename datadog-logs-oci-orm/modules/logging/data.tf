data "oci_logging_log_groups" "datadog_log_group" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
    display_name = "datadog-service-logs"
}

# Step 1: Fetch all compartments in the tenancy
data "oci_identity_compartments" "all_compartments" {
  compartment_id = var.tenancy_ocid
  state = "ACTIVE"
  compartment_id_in_subtree = true
}

# Step 2: Fetch all log groups in each compartment
data "oci_logging_log_groups" "log_groups_by_compartment" {
  for_each       = toset([for compartment in data.oci_identity_compartments.all_compartments.compartments : compartment.id])
  compartment_id = each.value
}

# Step 3: Fetch all logs from this compartment
data "oci_logging_logs" "existing_logs" {
    #Required
    for_each = { for log_group in data.oci_logging_log_groups.log_groups_by_compartment[var.compartment_ocid].log_groups : log_group.id => log_group }
    log_group_id = each.value.id
}

# Step 4: Fetch all logs in other compartments for resources without them
locals {
  flat_log_groups = flatten([
    for compartment_id, log_group_data in data.oci_logging_log_groups.log_groups_by_compartment : log_group_data.log_groups
    if compartment_id != var.compartment_ocid
  ])
  log_group_ids_string = join(",", [for lg in local.flat_log_groups : lg.id])
}

data "external" "logs_outside_compartment" {
    for_each = { for resource in local.resource_evaluation : "${resource.resource_id}-${resource.category}" => resource }
    program = [
      "bash",
      "modules/logging/search_logs_outside_compartment.sh",
      local.log_group_ids_string,
      each.value.resource_id,
      each.value.log_group != null ? "Y" : "N"
    ]
}
