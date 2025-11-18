#*************************************
#  Pre-deployment Validation Checks
#  (Native Terraform replacement for pre_check.py)
#*************************************

# Check 1: Validate home region is supported by Datadog
resource "terraform_data" "validate_home_region_support" {
  lifecycle {
    precondition {
      condition     = contains(local.supported_regions_list, local.home_region_name)
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                    HOME REGION NOT SUPPORTED ERROR                         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        Home region ${local.home_region_name} is not supported by Datadog.
        
        Supported regions: ${join(", ", local.supported_regions_list)}
        
        Please contact Datadog support if you need this region enabled.
      EOF
    }
  }
}

# Check 3: Validate user and group consistency
resource "terraform_data" "validate_user_group_consistency" {
  lifecycle {
    precondition {
      condition = (
        (var.existing_user_id == null || var.existing_user_id == "") && (var.existing_group_id == null || var.existing_group_id == "") ||
        (var.existing_user_id != null && var.existing_user_id != "") && (var.existing_group_id != null && var.existing_group_id != "")
      )
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   USER/GROUP CONFIGURATION ERROR                           ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Both existing_user_id and existing_group_id must be provided together,     ║
        ║ or both must be null/empty.                                                ║
        ║                                                                            ║
        ║                                                                            ║
        ║ Either:                                                                    ║
        ║   1. Leave both empty to create new user and group, OR                     ║
        ║   2. Provide both to use existing user and group                           ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 4: Validate domain_id and user_email consistency
resource "terraform_data" "validate_domain_email_consistency" {
  lifecycle {
    precondition {
      condition = (
        (var.domain_id == null || var.domain_id == "") && (var.user_email == null || var.user_email == "") ||
        (var.domain_id != null && var.domain_id != "") && (var.user_email != null && var.user_email != "")
      )
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   DOMAIN/EMAIL CONFIGURATION ERROR                         ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Both domain_id and user_email must be provided together,                  ║
        ║ or both must be null/empty.                                                ║
        ║                                                                            ║
        ║ Either:                                                                    ║
        ║   1. Leave both empty (default behavior), OR                               ║
        ║   2. Provide both domain_id and user_email together                        ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 5: Validate existing user/group cannot be used with domain_id/user_email
resource "terraform_data" "validate_existing_vs_new_user" {
  lifecycle {
    precondition {
      condition = !(
        (var.existing_user_id != null && var.existing_user_id != "" || var.existing_group_id != null && var.existing_group_id != "") &&
        (var.domain_id != null && var.domain_id != "" || var.user_email != null && var.user_email != "")
      )
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   CONFLICTING USER CONFIGURATION ERROR                     ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot specify both existing user/group AND domain_id/user_email.         ║
        ║                                                                            ║
        ║ You are using existing_user_id or existing_group_id, which means you are  ║
        ║ using pre-existing IAM resources.                                          ║
        ║                                                                            ║
        ║ The domain_id and user_email variables are only for creating NEW users.   ║
        ║                                                                            ║
        ║ Please remove domain_id and user_email from your configuration.           ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Data source: Check vault quota availability
data "oci_limits_resource_availability" "vault_quota" {
  compartment_id     = var.tenancy_ocid
  limit_name         = "virtual-vault-count"
  service_name       = "kms"
  availability_domain = null
}

# Check 9: Validate vault quota is available
resource "terraform_data" "validate_vault_quota" {
  lifecycle {
    precondition {
      condition     = try(data.oci_limits_resource_availability.vault_quota.available, 0) >= 1
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                         VAULT QUOTA EXHAUSTED ERROR                        ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        No vaults can be created in ${local.home_region_name}: vault quota exhausted.
        
        Available: ${try(data.oci_limits_resource_availability.vault_quota.available, 0)}
        Required: 1
        
        Please increase your vault quota or delete existing vaults.
      EOF
    }
  }
}

# Data source: Check service connector hub quota availability
data "oci_limits_resource_availability" "connector_hub_quota" {
  compartment_id      = var.tenancy_ocid
  limit_name          = "service-connector-count"
  service_name        = "service-connector-hub"
  availability_domain = null
}

# Check 10: Validate service connector hub quota is available
resource "terraform_data" "validate_connector_hub_quota" {
  lifecycle {
    precondition {
      condition     = try(data.oci_limits_resource_availability.connector_hub_quota.available, 0) >= 1
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   SERVICE CONNECTOR QUOTA EXHAUSTED ERROR                  ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        Insufficient connector hub quota in your tenancy.
        
        Available: ${try(data.oci_limits_resource_availability.connector_hub_quota.available, 0)}
        Required: 1
        
        Please increase your service connector quota.
      EOF
    }
  }
}

data "external" "check_integration_exists" {
  program = ["bash", "-c", <<-EOT
    # Check if integration resource exists in terraform state
    if terraform state list 2>/dev/null | grep -q "module.integration.restapi_object.datadog_tenancy_integration"; then
      echo '{"exists": "true"}'
    else
      echo '{"exists": "false"}'
    fi
  EOT
  ]
}

# Data source to check compartment mode changes
data "external" "check_compartment_mode" {
  program = ["bash", "-c", <<-EOT
    # Check what mode we're currently in
    CREATED_COMPARTMENT_EXISTS="false"
    USING_EXISTING_COMPARTMENT="false"
    CURRENT_COMPARTMENT_OCID=""
    
    # Check if we previously CREATED a compartment (var.resource_compartment_ocid was null)
    if terraform state list 2>/dev/null | grep -q "module.compartment.oci_identity_compartment.new\[0\]"; then
      CREATED_COMPARTMENT_EXISTS="true"
    fi
    
    # Check if we previously USED an existing compartment (var.resource_compartment_ocid was set)
    if terraform state list 2>/dev/null | grep -q "module.compartment.data.oci_identity_compartment.existing\[0\]"; then
      USING_EXISTING_COMPARTMENT="true"
      # Get the current compartment OCID from state
      CURRENT_COMPARTMENT_OCID=$(terraform state show 'module.compartment.data.oci_identity_compartment.existing[0]' 2>/dev/null | grep "^[[:space:]]*id[[:space:]]*=" | head -1 | sed 's/.*= "//' | sed 's/"//')
    fi
    
    # Determine if mode is changing
    # Mode change = switching from create->use-existing or use-existing->create
    MODE_CHANGING="false"
    OCID_CHANGING="false"
    
    if [ "$CREATED_COMPARTMENT_EXISTS" = "true" ] && [ "${var.resource_compartment_ocid != null ? "true" : "false"}" = "true" ]; then
      # Was creating, now wants to use existing
      MODE_CHANGING="true"
    fi
    
    if [ "$USING_EXISTING_COMPARTMENT" = "true" ] && [ "${var.resource_compartment_ocid != null ? "true" : "false"}" = "false" ]; then
      # Was using existing, now wants to create new
      MODE_CHANGING="true"
    fi
    
    # Check if the compartment OCID itself is changing (when using existing compartment)
    if [ "$USING_EXISTING_COMPARTMENT" = "true" ] && [ -n "$CURRENT_COMPARTMENT_OCID" ]; then
      DESIRED_COMPARTMENT_OCID="${var.resource_compartment_ocid != null ? var.resource_compartment_ocid : ""}"
      if [ -n "$DESIRED_COMPARTMENT_OCID" ] && [ "$CURRENT_COMPARTMENT_OCID" != "$DESIRED_COMPARTMENT_OCID" ]; then
        OCID_CHANGING="true"
      fi
    fi
    
    echo "{\"created_exists\": \"$CREATED_COMPARTMENT_EXISTS\", \"using_exists\": \"$USING_EXISTING_COMPARTMENT\", \"mode_changing\": \"$MODE_CHANGING\", \"ocid_changing\": \"$OCID_CHANGING\", \"current_ocid\": \"$CURRENT_COMPARTMENT_OCID\"}"
  EOT
  ]
}

# Data source to check user/group mode changes
data "external" "check_user_group_mode" {
  program = ["bash", "-c", <<-EOT
    # Check what mode we're currently in
    CREATED_USER_EXISTS="false"
    CREATED_GROUP_EXISTS="false"
    USING_EXISTING_USER="false"
    CURRENT_USER_OCID=""
    CURRENT_GROUP_OCID=""
    
    # Check if we previously CREATED a user and group (var.existing_user_id was null)
    if terraform state list 2>/dev/null | grep -q "module.auth\[0\].oci_identity_domains_user.dd_auth\[0\]"; then
      CREATED_USER_EXISTS="true"
    fi
    
    if terraform state list 2>/dev/null | grep -q "module.auth\[0\].oci_identity_domains_group.dd_auth\[0\]"; then
      CREATED_GROUP_EXISTS="true"
    fi
    
    # Check if we previously USED existing user/group
    # The data sources exist when we're using existing ones
    if terraform state list 2>/dev/null | grep -q "module.auth\[0\].data.oci_identity_domains_users.existing_user_with_groups\[0\]"; then
      USING_EXISTING_USER="true"
      # Get current user and group OCIDs from state
      CURRENT_USER_OCID=$(grep -o '"existing_user_id"[[:space:]]*:[[:space:]]*"[^"]*"' terraform.tfstate 2>/dev/null | head -1 | sed 's/.*:.*"\([^"]*\)".*/\1/')
      CURRENT_GROUP_OCID=$(grep -o '"existing_group_id"[[:space:]]*:[[:space:]]*"[^"]*"' terraform.tfstate 2>/dev/null | head -1 | sed 's/.*:.*"\([^"]*\)".*/\1/')
    fi
    
    # Determine if mode is changing
    MODE_CHANGING="false"
    USER_OCID_CHANGING="false"
    GROUP_OCID_CHANGING="false"
    
    USER_PROVIDED="${var.existing_user_id != null && var.existing_user_id != "" ? "true" : "false"}"
    GROUP_PROVIDED="${var.existing_group_id != null && var.existing_group_id != "" ? "true" : "false"}"
    
    # Was creating user/group, now wants to use existing
    if [ "$CREATED_USER_EXISTS" = "true" ] || [ "$CREATED_GROUP_EXISTS" = "true" ]; then
      if [ "$USER_PROVIDED" = "true" ] || [ "$GROUP_PROVIDED" = "true" ]; then
        MODE_CHANGING="true"
      fi
    fi
    
    # Was using existing user/group, now wants to create new
    if [ "$USING_EXISTING_USER" = "true" ]; then
      if [ "$USER_PROVIDED" = "false" ] || [ "$GROUP_PROVIDED" = "false" ]; then
        MODE_CHANGING="true"
      fi
    fi
    
    # Check if user OCID is changing (when using existing user/group)
    if [ "$USING_EXISTING_USER" = "true" ] && [ -n "$CURRENT_USER_OCID" ]; then
      DESIRED_USER_OCID="${var.existing_user_id != null && var.existing_user_id != "" ? var.existing_user_id : ""}"
      if [ -n "$DESIRED_USER_OCID" ] && [ "$CURRENT_USER_OCID" != "$DESIRED_USER_OCID" ]; then
        USER_OCID_CHANGING="true"
      fi
    fi
    
    # Check if group OCID is changing (when using existing user/group)
    if [ "$USING_EXISTING_USER" = "true" ] && [ -n "$CURRENT_GROUP_OCID" ]; then
      DESIRED_GROUP_OCID="${var.existing_group_id != null && var.existing_group_id != "" ? var.existing_group_id : ""}"
      if [ -n "$DESIRED_GROUP_OCID" ] && [ "$CURRENT_GROUP_OCID" != "$DESIRED_GROUP_OCID" ]; then
        GROUP_OCID_CHANGING="true"
      fi
    fi
    
    echo "{\"created_user_exists\": \"$CREATED_USER_EXISTS\", \"created_group_exists\": \"$CREATED_GROUP_EXISTS\", \"using_exists\": \"$USING_EXISTING_USER\", \"mode_changing\": \"$MODE_CHANGING\", \"user_ocid_changing\": \"$USER_OCID_CHANGING\", \"group_ocid_changing\": \"$GROUP_OCID_CHANGING\", \"current_user_ocid\": \"$CURRENT_USER_OCID\", \"current_group_ocid\": \"$CURRENT_GROUP_OCID\"}"
  EOT
  ]
}

# Check 12: Prevent compartment mode changes
resource "terraform_data" "validate_compartment_immutability" {
  lifecycle {
    precondition {
      condition     = data.external.check_compartment_mode.result.mode_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                    COMPARTMENT MODE CHANGE ERROR                           ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change resource_compartment_ocid after initial deployment.          ║
        ║                                                                            ║
        ║ You are trying to switch between:                                          ║
        ║   • Creating a new compartment (resource_compartment_ocid = null)          ║
        ║   • Using an existing compartment (resource_compartment_ocid = "ocid1...")  ║
        ║                                                                            ║
        ║ This would destroy and recreate ALL resources, including:                  ║
        ║   • Vault (7+ day deletion period)                                         ║
        ║   • Functions, VCNs, subnets, service connectors                           ║
        ║   • Authentication resources                                               ║
        ║                                                                            ║
        ║ To change compartments:                                                    ║
        ║   1. Run: terraform destroy                                                ║
        ║   2. Update resource_compartment_ocid in terraform.tfvars                  ║
        ║   3. Run: terraform apply                                                  ║
        ║                                                                            ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
    precondition {
      condition     = data.external.check_compartment_mode.result.ocid_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                    COMPARTMENT OCID CHANGE ERROR                           ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change the resource_compartment_ocid OCID after initial deployment. ║
        ║                                                                            ║
        ║                                                                            ║
        ║ You are trying to switch from one existing compartment to another.         ║
        ║ This would destroy and recreate ALL resources, including:                  ║
        ║   • Vault (7+ day deletion period)                                         ║
        ║   • Functions, VCNs, subnets, service connectors                           ║
        ║   • Authentication resources                                               ║
        ║                                                                            ║
        ║ To change to a different compartment:                                      ║
        ║   1. Run: terraform destroy                                                ║
        ║   2. Update resource_compartment_ocid in terraform.tfvars                  ║
        ║   3. Run: terraform apply                                                  ║
        ║                                                                            ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 13: Prevent user/group mode changes
resource "terraform_data" "validate_user_group_immutability" {
  lifecycle {
    precondition {
      condition     = data.external.check_user_group_mode.result.mode_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   USER/GROUP MODE CHANGE ERROR                             ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change existing_user_id/existing_group_id after deployment.         ║
        ║                                                                            ║
        ║                                                                            ║
        ║ This would destroy and recreate authentication resources, including:       ║
        ║   • API keys (integration would break)                                     ║
        ║   • User and group resources                                               ║
        ║   • Policies and permissions                                               ║
        ║                                                                            ║
        ║ To change user/group:                                                      ║
        ║   1. Run: terraform destroy                                                ║
        ║   2. Update existing_user_id/existing_group_id in terraform.tfvars         ║
        ║   3. Run: terraform apply                                                  ║
        ║                                                                            ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
    precondition {
      condition     = data.external.check_user_group_mode.result.user_ocid_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   EXISTING USER OCID CHANGE ERROR                          ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change existing_user_id OCID after initial deployment.              ║
        ║                                                                            ║
        ║                                                                            ║
        ║ Changing the user would destroy and recreate:                              ║
        ║   • API keys (integration would break immediately)                         ║
        ║   • User authentication credentials                                        ║
        ║   • All policies attached to this user                                     ║
        ║                                                                            ║
        ║ To change to a different user:                                             ║
        ║   1. Run: terraform destroy                                                ║
        ║   2. Update existing_user_id in terraform.tfvars                           ║
        ║   3. Run: terraform apply                                                  ║
        ║                                                                            ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
    precondition {
      condition     = data.external.check_user_group_mode.result.group_ocid_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   EXISTING GROUP OCID CHANGE ERROR                         ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change existing_group_id OCID after initial deployment.             ║
        ║                                                                            ║
        ║                                                                            ║
        ║ Changing the group would destroy and recreate:                             ║
        ║   • All policies attached to this group                                    ║
        ║   • Group permissions and access controls                                  ║
        ║   • Integration authorization                                              ║
        ║                                                                            ║
        ║ To change to a different group:                                            ║
        ║   1. Run: terraform destroy                                                ║
        ║   2. Update existing_group_id in terraform.tfvars                          ║
        ║   3. Run: terraform apply                                                  ║
        ║                                                                            ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Marker resource to indicate all prechecks have passed
# Other resources can depend on this instead of null_resource.precheck_marker
resource "terraform_data" "prechecks_complete" {
  depends_on = [
    terraform_data.validate_home_region_support,
    terraform_data.validate_user_group_consistency,
    terraform_data.validate_domain_email_consistency,
    terraform_data.validate_existing_vs_new_user,
    terraform_data.validate_vault_quota,
    terraform_data.validate_connector_hub_quota,
    terraform_data.validate_compartment_immutability,
    terraform_data.validate_user_group_immutability,
  ]
}

