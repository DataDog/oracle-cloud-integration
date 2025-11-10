terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}

# Stage 1: Validate that both user and group variables are either both null/empty OR both provided
resource "null_resource" "user_group_variable_validation" {
  
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command = <<-EOT
      # Check variable consistency
      USER_PROVIDED="${var.existing_user_id != null && var.existing_user_id != "" ? "true" : "false"}"
      GROUP_PROVIDED="${var.existing_group_id != null && var.existing_group_id != "" ? "true" : "false"}"
      
      if [ "$USER_PROVIDED" != "$GROUP_PROVIDED" ]; then
        echo "ERROR: Both existing_user_id and existing_group_id must be provided together, or both must be null/empty."
        echo "Current state:"
        echo "  existing_user_id: ${var.existing_user_id != null ? var.existing_user_id : "null/empty"}"
        echo "  existing_group_id: ${var.existing_group_id != null ? var.existing_group_id : "null/empty"}"
        exit 1
      fi
      
      if [ "$USER_PROVIDED" = "false" ] && [ "$GROUP_PROVIDED" = "false" ]; then
        echo "✅ No existing user/group provided - will create new ones"
      else
        echo "✅ Both existing user and group provided - will validate them in next stage"
      fi
    EOT
  }
}

# Stage 2: Validate data sources only when both variables are provided
resource "null_resource" "existing_user_group_validation" {
  count = var.existing_user_id != null && var.existing_user_id != "" && var.existing_group_id != null && var.existing_group_id != "" ? 1 : 0
  
  depends_on = [null_resource.user_group_variable_validation]
  
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command = <<-EOT
      # First check if the data sources returned any results
      USER_DATA_COUNT=${length(data.oci_identity_domains_users.existing_user_with_groups)}
      GROUP_DATA_COUNT=${length(data.oci_identity_domains_groups.existing_group)}
      
      if [ $USER_DATA_COUNT -eq 0 ]; then
        echo "ERROR: No user data found for OCID '${var.existing_user_id}'"
        echo "This could mean:"
        echo "  - The OCID is invalid or malformed"
        echo "  - The user does not exist in this Identity Domain"
        echo "  - The OCID belongs to a different Identity Domain"
        echo "  - You don't have permission to read this user"
        exit 1
      fi
      
      if [ $GROUP_DATA_COUNT -eq 0 ]; then
        echo "ERROR: No group data found for OCID '${var.existing_group_id}'"
        echo "This could mean:"
        echo "  - The OCID is invalid or malformed"
        echo "  - The group does not exist in this Identity Domain"
        echo "  - The OCID belongs to a different Identity Domain"
        echo "  - You don't have permission to read this group"
        exit 1
      fi
      
      # Now check if the SCIM filter found actual users and groups
      USER_COUNT=${length(data.oci_identity_domains_users.existing_user_with_groups[0].users)}
      GROUP_COUNT=${length(data.oci_identity_domains_groups.existing_group[0].groups)}
      
      if [ $USER_COUNT -eq 0 ]; then
        echo "ERROR: No user found with OCID '${var.existing_user_id}'"
        echo "This could mean:"
        echo "  - The OCID is invalid or malformed"
        echo "  - The user does not exist in this Identity Domain"
        echo "  - The OCID belongs to a different Identity Domain"
        echo "  - You don't have permission to read this user"
        exit 1
      fi
      
      if [ $GROUP_COUNT -eq 0 ]; then
        echo "ERROR: No group found with OCID '${var.existing_group_id}'"
        echo "This could mean:"
        echo "  - The OCID is invalid or malformed"
        echo "  - The group does not exist in this Identity Domain"
        echo "  - The OCID belongs to a different Identity Domain"
        echo "  - You don't have permission to read this group"
        exit 1
      fi
      
      # Only check group membership if both user and group exist
      # The user's groups are in data.oci_identity_domains_users.existing_user_with_groups[0].users[0].groups[*].ocid
      USER_GROUPS_JSON='${jsonencode(length(data.oci_identity_domains_users.existing_user_with_groups[0].users) > 0 ? data.oci_identity_domains_users.existing_user_with_groups[0].users[0].groups : [])}'
      USER_GROUPS=$(echo "$USER_GROUPS_JSON" | grep -o '"ocid":"[^"]*"' | cut -d'"' -f4 || echo "")
      TARGET_GROUP_OCID="${var.existing_group_id}"
      
      if echo "$USER_GROUPS" | grep -q "$TARGET_GROUP_OCID"; then
        echo "✅ User '${var.existing_user_id}' is a member of group '${var.existing_group_id}'"
      else
        echo "ERROR: User '${var.existing_user_id}' is not a member of group '${var.existing_group_id}'"
        echo "User's current group memberships:"
        echo "$USER_GROUPS"
        exit 1
      fi
    EOT
  }
}

resource "oci_identity_domains_user" "dd_auth" {
  depends_on    = [null_resource.user_group_variable_validation]
  count         = var.existing_user_id == null || var.existing_user_id == "" ? 1 : 0
  idcs_endpoint = var.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User", "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"]
  user_name     = var.user_name
  emails {
    primary = true
    value   = local.email
    type    = "work"
  }
  name {
    family_name = var.user_name
    given_name  = var.user_name
  }
  display_name = var.user_name

  urnietfparamsscimschemasoracleidcsextension_oci_tags {
    dynamic "freeform_tags" {
      for_each = var.tags
      content {
        key   = freeform_tags.key
        value = freeform_tags.value
      }
    }
  }
}

# Wait for user to appear in Identity Domains list API
resource "time_sleep" "wait_for_user_propagation" {
  count           = var.existing_user_id == null || var.existing_user_id == "" ? 1 : 0
  depends_on      = [oci_identity_domains_user.dd_auth]
  create_duration = "30s"
}

resource "oci_identity_domains_group" "dd_auth" {
  depends_on    = [null_resource.user_group_variable_validation]
  count         = var.existing_group_id == null || var.existing_group_id == "" ? 1 : 0
  idcs_endpoint = var.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = var.user_group_name

  # Add user to group
  members {
    value = var.existing_user_id != null && var.existing_user_id != "" ? var.existing_user_id : oci_identity_domains_user.dd_auth[0].id
    type  = "User"
  }

  urnietfparamsscimschemasoracleidcsextension_oci_tags {
    dynamic "freeform_tags" {
      for_each = var.tags
      content {
        key   = freeform_tags.key
        value = freeform_tags.value
      }
    }
  }
}

resource "oci_identity_policy" "dd_auth" {
  depends_on     = [null_resource.user_group_variable_validation, oci_identity_domains_group.dd_auth]
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policies required by Datadog User"
  name           = var.user_policy_name
  statements = [
    "Define tenancy usage-report as ocid1.tenancy.oc1..aaaaaaaaned4fkpkisbwjlr56u7cj63lf3wffbilvqknstgtvzub7vhqkggq",
    "Allow group id ${var.existing_group_id != null && var.existing_group_id != "" ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].ocid} to read all-resources in tenancy",
    "Allow group id ${var.existing_group_id != null && var.existing_group_id != "" ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].ocid} to manage serviceconnectors in compartment id ${var.compartment_id}",
    "Allow group id ${var.existing_group_id != null && var.existing_group_id != "" ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].ocid} to manage functions-family in compartment id ${var.compartment_id} where ANY {request.permission = 'FN_FUNCTION_UPDATE', request.permission = 'FN_FUNCTION_LIST', request.permission = 'FN_APP_LIST'}",
    "Endorse group id ${var.existing_group_id != null && var.existing_group_id != "" ? var.existing_group_id : oci_identity_domains_group.dd_auth[0].ocid} to read objects in tenancy usage-report"
  ]
  freeform_tags = var.tags
}

resource "oci_identity_domains_dynamic_resource_group" "service_connector" {
  depends_on    = [null_resource.user_group_variable_validation]
  idcs_endpoint = var.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]
  display_name  = var.dg_sch_name
  description   = "[DO NOT REMOVE] Dynamic group for forwarding by service connector"
  matching_rule = "All {resource.type = 'serviceconnector', resource.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_domains_dynamic_resource_group" "forwarding_function" {
  depends_on    = [null_resource.user_group_variable_validation]
  idcs_endpoint = var.idcs_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]
  display_name  = var.dg_fn_name
  description   = "[DO NOT REMOVE] Dynamic group for forwarding functions"
  matching_rule = "All {resource.type = 'fnfunc', resource.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_policy" "dynamic_group" {
  depends_on     = [null_resource.user_group_variable_validation, oci_identity_domains_dynamic_resource_group.service_connector]
  compartment_id = var.tenancy_id
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from eligible sources and write to a target function"
  name           = var.dg_policy_name
  statements = [
    "Allow dynamic-group id ${oci_identity_domains_dynamic_resource_group.service_connector.ocid} to read log-content in tenancy",
    "Allow dynamic-group id ${oci_identity_domains_dynamic_resource_group.service_connector.ocid} to read metrics in tenancy",
    "Allow dynamic-group id ${oci_identity_domains_dynamic_resource_group.service_connector.ocid} to use fn-function in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_domains_dynamic_resource_group.service_connector.ocid} to use fn-invocation in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_domains_dynamic_resource_group.forwarding_function.ocid} to read secret-bundles in compartment id ${var.compartment_id}"
  ]
  freeform_tags = var.tags
}
