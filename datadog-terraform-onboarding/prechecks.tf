#*************************************
#  Pre-deployment Validation Checks
#  (Native Terraform replacement for pre_check.py)
#*************************************

# Check 1: Validate we're deploying in home region
resource "terraform_data" "validate_home_region" {
  lifecycle {
    precondition {
      condition     = local.is_current_region_home_region
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                       HOME REGION MISMATCH ERROR                           ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        This stack must be deployed in the tenancy's home region.
        
        Current region: ${var.region}
        Home region: ${local.home_region_name}
        
        Please update your region variable to match the home region.
      EOF
    }
  }
}

# Check 2: Validate home region is supported by Datadog
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
        ║ Both existing_user_id and existing_group_id must be provided together,    ║
        ║ or both must be null/empty.                                               ║
        ║                                                                            ║
        ║                                                                            ║
        ║ Either:                                                                   ║
        ║   1. Leave both empty to create new user and group, OR                    ║
        ║   2. Provide both to use existing user and group                          ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Resource existence checks removed - Terraform and OCI will handle duplicate resource conflicts
# with clear error messages. For pure Terraform workflows, these checks are redundant.

# Data source: Check vault quota availability
data "oci_limits_resource_availability" "vault_quota" {
  count              = local.is_current_region_home_region ? 1 : 0
  compartment_id     = var.tenancy_ocid
  limit_name         = "virtual-vault-count"
  service_name       = "kms"
  availability_domain = null
}

# Check 9: Validate vault quota is available
resource "terraform_data" "validate_vault_quota" {
  count = local.is_current_region_home_region ? 1 : 0
  
  lifecycle {
    precondition {
      condition     = try(data.oci_limits_resource_availability.vault_quota[0].available, 0) >= 1
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                         VAULT QUOTA EXHAUSTED ERROR                        ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        No vaults can be created in ${local.home_region_name}: vault quota exhausted.
        
        Available: ${try(data.oci_limits_resource_availability.vault_quota[0].available, 0)}
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
        
        Insufficient connector hub quota in ${var.region}.
        
        Available: ${try(data.oci_limits_resource_availability.connector_hub_quota.available, 0)}
        Required: 1
        
        Please increase your service connector quota.
      EOF
    }
  }
}

# Check 10: Validate enabled regions are subscribed
resource "terraform_data" "validate_enabled_regions" {
  count = length(var.enabled_regions) > 0 ? 1 : 0
  
  lifecycle {
    precondition {
      condition = alltrue([
        for region in var.enabled_regions : contains(local.subscribed_regions_list, region)
      ])
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                         ENABLED REGIONS ERROR                              ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ One or more enabled regions are not in your subscribed regions list.      ║
        ║                                                                            ║
        ║ Enabled regions must be from your tenancy's subscribed regions.           ║
        ║                                                                            ║
        ║ Enabled regions: ${jsonencode(var.enabled_regions)}
        ║                                                                            ║
        ║ Available subscribed regions: ${jsonencode(local.subscribed_regions_list)}
        ║                                                                            ║
        ║ Please update 'enabled_regions' to only include subscribed regions.       ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 11: Validate enabled regions have corresponding subnets when subnets are specified
resource "terraform_data" "validate_enabled_regions_have_subnets" {
  count = length(var.enabled_regions) > 0 && length(local.subnet_ocids_list) > 0 ? 1 : 0
  
  lifecycle {
    precondition {
      condition = alltrue([
        for region in var.enabled_regions : contains(tolist(local.subnet_regions), region)
      ])
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║              ENABLED REGIONS MISSING SUBNETS ERROR                         ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ When you specify both 'enabled_regions' and 'subnet_ocids', every enabled ║
        ║ region must have a corresponding subnet for infrastructure deployment.     ║
        ║                                                                            ║
        ║ Enabled regions: ${jsonencode(var.enabled_regions)}
        ║                                                                            ║
        ║ Regions with subnets: ${jsonencode(sort(tolist(local.subnet_regions)))}
        ║                                                                            ║
        ║ SOLUTION: Either add subnets for the missing regions, or remove those     ║
        ║ regions from 'enabled_regions', or omit 'subnet_ocids' to auto-create.    ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}


# Data source to check if integration already exists in state
data "external" "check_integration_exists" {
  program = ["bash", "-c", <<-EOT
    # Check if integration resource exists in terraform state
    if terraform state list 2>/dev/null | grep -q "module.integration\[0\].restapi_object.datadog_tenancy_integration"; then
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
    
    # Check if we previously CREATED a compartment (var.compartment_id was null)
    if terraform state list 2>/dev/null | grep -q "module.compartment.oci_identity_compartment.new\[0\]"; then
      CREATED_COMPARTMENT_EXISTS="true"
    fi
    
    # Check if we previously USED an existing compartment (var.compartment_id was set)
    if terraform state list 2>/dev/null | grep -q "module.compartment.data.oci_identity_compartment.existing\[0\]"; then
      USING_EXISTING_COMPARTMENT="true"
      # Get the current compartment OCID from state
      CURRENT_COMPARTMENT_OCID=$(terraform state show 'module.compartment.data.oci_identity_compartment.existing[0]' 2>/dev/null | grep "^[[:space:]]*id[[:space:]]*=" | head -1 | sed 's/.*= "//' | sed 's/"//')
    fi
    
    # Determine if mode is changing
    # Mode change = switching from create->use-existing or use-existing->create
    MODE_CHANGING="false"
    OCID_CHANGING="false"
    
    if [ "$CREATED_COMPARTMENT_EXISTS" = "true" ] && [ "${var.compartment_id != null ? "true" : "false"}" = "true" ]; then
      # Was creating, now wants to use existing
      MODE_CHANGING="true"
    fi
    
    if [ "$USING_EXISTING_COMPARTMENT" = "true" ] && [ "${var.compartment_id != null ? "true" : "false"}" = "false" ]; then
      # Was using existing, now wants to create new
      MODE_CHANGING="true"
    fi
    
    # Check if the compartment OCID itself is changing (when using existing compartment)
    if [ "$USING_EXISTING_COMPARTMENT" = "true" ] && [ -n "$CURRENT_COMPARTMENT_OCID" ]; then
      DESIRED_COMPARTMENT_OCID="${var.compartment_id != null ? var.compartment_id : ""}"
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

# Data source to check if parent compartment is being changed
data "external" "check_parent_compartment_change" {
  program = ["bash", "-c", <<-EOT
    # Check if we created a compartment (not using existing)
    CREATED_COMPARTMENT="false"
    USING_EXISTING_COMPARTMENT="false"
    
    if terraform state list 2>/dev/null | grep -q "module.compartment.oci_identity_compartment.new\[0\]"; then
      CREATED_COMPARTMENT="true"
    fi
    
    if terraform state list 2>/dev/null | grep -q "module.compartment.data.oci_identity_compartment.existing\[0\]"; then
      USING_EXISTING_COMPARTMENT="true"
    fi
    
    # Get the parent compartment from state (when created)
    CURRENT_PARENT=""
    if [ "$CREATED_COMPARTMENT" = "true" ]; then
      CURRENT_PARENT=$(terraform state show 'module.compartment.oci_identity_compartment.new[0]' 2>/dev/null | grep "compartment_id" | head -1 | sed 's/.*= "//' | sed 's/"//')
    fi
    
    # Get current compartment_ocid from state for any deployment mode
    CURRENT_COMPARTMENT_OCID=""
    if [ "$CREATED_COMPARTMENT" = "true" ] || [ "$USING_EXISTING_COMPARTMENT" = "true" ]; then
      # Try to get from terraform.tfstate directly as a fallback
      CURRENT_COMPARTMENT_OCID=$(grep -o '"compartment_ocid"[[:space:]]*:[[:space:]]*"[^"]*"' terraform.tfstate 2>/dev/null | head -1 | sed 's/.*:.*"\([^"]*\)".*/\1/')
    fi
    
    # Get the desired parent from variable
    DESIRED_PARENT="${var.compartment_ocid}"
    
    # Check if parent is changing (when created compartment)
    PARENT_CHANGING="false"
    if [ "$CREATED_COMPARTMENT" = "true" ] && [ -n "$CURRENT_PARENT" ] && [ "$CURRENT_PARENT" != "$DESIRED_PARENT" ]; then
      PARENT_CHANGING="true"
    fi
    
    # Check if compartment_ocid itself is changing (for any mode)
    COMPARTMENT_OCID_CHANGING="false"
    if [ -n "$CURRENT_COMPARTMENT_OCID" ] && [ "$CURRENT_COMPARTMENT_OCID" != "$DESIRED_PARENT" ]; then
      COMPARTMENT_OCID_CHANGING="true"
    fi
    
    echo "{\"created_compartment\": \"$CREATED_COMPARTMENT\", \"current_parent\": \"$CURRENT_PARENT\", \"desired_parent\": \"$DESIRED_PARENT\", \"parent_changing\": \"$PARENT_CHANGING\", \"current_compartment_ocid\": \"$CURRENT_COMPARTMENT_OCID\", \"compartment_ocid_changing\": \"$COMPARTMENT_OCID_CHANGING\"}"
  EOT
  ]
}

# Data source to check if infrastructure regions are being removed
data "external" "check_infrastructure_regions_removal" {
  program = ["bash", "-c", <<-EOT
    # Get list of regions with deployed infrastructure
    DEPLOYED_REGIONS=$(terraform state list 2>/dev/null | grep "module.regional_deployment_" | sed 's/module.regional_deployment_//' | sed 's/\[0\].*//' | tr '_' '-' | sort -u | tr '\n' ',' | sed 's/,$//')
    
    # Check if subnet_ocids is being used to control regions
    SUBNET_OCIDS_USED="${var.subnet_ocids != "" ? "true" : "false"}"
    
    # Get regions from current subnet OCIDs
    CURRENT_SUBNET_REGIONS="${join(",", [for s in split("\n", var.subnet_ocids) : length(split(".", trimspace(s))) >= 4 ? replace(split(".", trimspace(s))[3], "_", "-") : "" if trimspace(s) != ""])}"
    
    # Check if any deployed region would lose its infrastructure
    REGIONS_REMOVED="false"
    REMOVED_REGIONS=""
    
    if [ "$SUBNET_OCIDS_USED" = "true" ] && [ -n "$DEPLOYED_REGIONS" ]; then
      # Convert to arrays
      IFS=',' read -ra DEPLOYED <<< "$DEPLOYED_REGIONS"
      
      for region in "$${DEPLOYED[@]}"; do
        [ -z "$region" ] && continue
        
        # Check if this deployed region is still in current subnet regions
        if ! echo ",$CURRENT_SUBNET_REGIONS," | grep -q ",$region,"; then
          REGIONS_REMOVED="true"
          if [ -z "$REMOVED_REGIONS" ]; then
            REMOVED_REGIONS="$region"
          else
            REMOVED_REGIONS="$REMOVED_REGIONS,$region"
          fi
        fi
      done
    fi
    
    echo "{\"deployed_regions\": \"$DEPLOYED_REGIONS\", \"subnet_regions\": \"$CURRENT_SUBNET_REGIONS\", \"regions_removed\": \"$REGIONS_REMOVED\", \"removed_regions\": \"$REMOVED_REGIONS\"}"
  EOT
  ]
}

# Check 11: Prevent parent compartment changes
resource "terraform_data" "validate_parent_compartment_immutability" {
  lifecycle {
    precondition {
      condition     = data.external.check_parent_compartment_change.result.parent_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                 PARENT COMPARTMENT CHANGE ERROR                            ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change compartment_ocid after creating a compartment.              ║
        ║                                                                            ║
        ║ Current parent compartment: ${data.external.check_parent_compartment_change.result.current_parent}
        ║                                                                            ║
        ║ New parent compartment:     ${data.external.check_parent_compartment_change.result.desired_parent}
        ║                                                                            ║
        ║ You created a "Datadog" compartment under the original compartment_ocid.  ║
        ║ Changing the parent would cause Terraform to:                             ║
        ║   • Not find the existing compartment (wrong parent)                      ║
        ║   • Try to create a NEW compartment under the new parent                  ║
        ║   • Destroy and recreate ALL resources                                    ║
        ║                                                                            ║
        ║ To change the parent compartment:                                         ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update compartment_ocid in terraform.tfvars                          ║
        ║   3. Run: terraform apply                                                 ║
        ║   4. Wait 7+ days for vault deletion                                      ║
        ║                                                                            ║
        ║ Set compartment_ocid correctly BEFORE your first terraform apply!         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
    precondition {
      condition     = data.external.check_parent_compartment_change.result.compartment_ocid_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                 COMPARTMENT_OCID CHANGE ERROR                              ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change compartment_ocid after initial deployment.                  ║
        ║                                                                            ║
        ║ Current compartment_ocid: ${data.external.check_parent_compartment_change.result.current_compartment_ocid}
        ║                                                                            ║
        ║ New compartment_ocid:     ${data.external.check_parent_compartment_change.result.desired_parent}
        ║                                                                            ║
        ║ Changing compartment_ocid would cause Terraform to:                       ║
        ║   • Deploy resources to a different compartment hierarchy                 ║
        ║   • Potentially orphan existing resources                                 ║
        ║   • Destroy and recreate ALL resources                                    ║
        ║                                                                            ║
        ║ To change compartment_ocid:                                               ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update compartment_ocid in terraform.tfvars                          ║
        ║   3. Run: terraform apply                                                 ║
        ║   4. Wait 7+ days for vault deletion                                      ║
        ║                                                                            ║
        ║ Set compartment_ocid correctly BEFORE your first terraform apply!         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 12: Prevent removing infrastructure from deployed regions
resource "terraform_data" "validate_infrastructure_regions_removal" {
  lifecycle {
    precondition {
      condition     = data.external.check_infrastructure_regions_removal.result.regions_removed != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                 INFRASTRUCTURE REGIONS REMOVAL ERROR                       ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot modify available regions after deployment.               ║
        ║                                                                            ║
        ║ Regions with deployed infrastructure: ${data.external.check_infrastructure_regions_removal.result.deployed_regions}
        ║                                                                            ║
        ║                                                                            ║
        ║ These regions have active infrastructure (functions, connector hubs, VCNs)║
        ║ Changing subnet_ocids to exclude them would destroy this infrastructure.  ║
        ║                                                                            ║
        ║ You CAN:                                                                  ║
        ║   ✅ Add new regions (add more subnet OCIDs)                              ║
        ║   ✅ Keep all existing regions in subnet_ocids                            ║
        ║                                                                            ║
        ║ To remove regional infrastructure:                                        ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update subnet_ocids in terraform.tfvars                              ║
        ║   3. Run: terraform apply                                                 ║
        ║   4. Wait 7+ days for vault deletion                                      ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 13: Prevent compartment mode changes
resource "terraform_data" "validate_compartment_immutability" {
  lifecycle {
    precondition {
      condition     = data.external.check_compartment_mode.result.mode_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                    COMPARTMENT MODE CHANGE ERROR                           ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change compartment_id after initial deployment.                    ║
        ║                                                                            ║
        ║ You are trying to switch between:                                         ║
        ║   • Creating a new compartment (compartment_id = null)                    ║
        ║   • Using an existing compartment (compartment_id = "ocid1...")           ║
        ║                                                                            ║
        ║ This would destroy and recreate ALL resources, including:                 ║
        ║   • Vault (7+ day deletion period)                                        ║
        ║   • Functions, VCNs, subnets, service connectors                          ║
        ║   • Authentication resources                                              ║
        ║                                                                            ║
        ║ To change compartments:                                                   ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update compartment_id in terraform.tfvars                            ║
        ║   3. Run: terraform apply                                                 ║
        ║   4. Wait 7+ days for vault deletion                                      ║
        ║                                                                            ║
        ║ Set compartment_id correctly BEFORE your first terraform apply!           ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
    precondition {
      condition     = data.external.check_compartment_mode.result.ocid_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                    COMPARTMENT OCID CHANGE ERROR                           ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change the compartment_id OCID after initial deployment.          ║
        ║                                                                            ║
        ║ Current compartment: ${data.external.check_compartment_mode.result.current_ocid}
        ║                                                                            ║
        ║ New compartment:     ${var.compartment_id != null ? var.compartment_id : "null"}
        ║                                                                            ║
        ║ You are trying to switch from one existing compartment to another.       ║
        ║ This would destroy and recreate ALL resources, including:                 ║
        ║   • Vault (7+ day deletion period)                                        ║
        ║   • Functions, VCNs, subnets, service connectors                          ║
        ║   • Authentication resources                                              ║
        ║                                                                            ║
        ║ To change to a different compartment:                                     ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update compartment_id in terraform.tfvars                            ║
        ║   3. Run: terraform apply                                                 ║
        ║   4. Wait 7+ days for vault deletion                                      ║
        ║                                                                            ║
        ║ Set compartment_id correctly BEFORE your first terraform apply!           ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 14: Prevent user/group mode changes
resource "terraform_data" "validate_user_group_immutability" {
  lifecycle {
    precondition {
      condition     = data.external.check_user_group_mode.result.mode_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   USER/GROUP MODE CHANGE ERROR                             ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change existing_user_id/existing_group_id after deployment.        ║
        ║                                                                            ║
        ║ You are trying to switch between:                                         ║
        ║   • Creating new user/group (existing_user_id = null)                     ║
        ║   • Using existing user/group (existing_user_id = "ocid1...")             ║
        ║                                                                            ║
        ║ This would destroy and recreate authentication resources, including:      ║
        ║   • API keys (integration would break)                                    ║
        ║   • User and group resources                                              ║
        ║   • Policies and permissions                                              ║
        ║                                                                            ║
        ║ To change user/group:                                                     ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update existing_user_id/existing_group_id in terraform.tfvars        ║
        ║   3. Run: terraform apply                                                 ║
        ║                                                                            ║
        ║ Set these correctly BEFORE your first terraform apply!                    ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
    precondition {
      condition     = data.external.check_user_group_mode.result.user_ocid_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   EXISTING USER OCID CHANGE ERROR                          ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change existing_user_id OCID after initial deployment.            ║
        ║                                                                            ║
        ║ Current user: ${data.external.check_user_group_mode.result.current_user_ocid}
        ║                                                                            ║
        ║ New user:     ${var.existing_user_id != null ? var.existing_user_id : "null"}
        ║                                                                            ║
        ║ Changing the user would destroy and recreate:                             ║
        ║   • API keys (integration would break immediately)                        ║
        ║   • User authentication credentials                                       ║
        ║   • All policies attached to this user                                    ║
        ║                                                                            ║
        ║ To change to a different user:                                            ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update existing_user_id in terraform.tfvars                          ║
        ║   3. Run: terraform apply                                                 ║
        ║                                                                            ║
        ║ Set existing_user_id correctly BEFORE your first terraform apply!         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
    precondition {
      condition     = data.external.check_user_group_mode.result.group_ocid_changing != "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                   EXISTING GROUP OCID CHANGE ERROR                         ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cannot change existing_group_id OCID after initial deployment.           ║
        ║                                                                            ║
        ║ Current group: ${data.external.check_user_group_mode.result.current_group_ocid}
        ║                                                                            ║
        ║ New group:     ${var.existing_group_id != null ? var.existing_group_id : "null"}
        ║                                                                            ║
        ║ Changing the group would destroy and recreate:                            ║
        ║   • All policies attached to this group                                   ║
        ║   • Group permissions and access controls                                 ║
        ║   • Integration authorization                                             ║
        ║                                                                            ║
        ║ To change to a different group:                                           ║
        ║   1. Run: terraform destroy                                               ║
        ║   2. Update existing_group_id in terraform.tfvars                         ║
        ║   3. Run: terraform apply                                                 ║
        ║                                                                            ║
        ║ Set existing_group_id correctly BEFORE your first terraform apply!        ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Check 13: Prevent cost collection at initial creation
resource "terraform_data" "validate_cost_collection_timing" {
  count = var.cost_collection_enabled ? 1 : 0
  
  lifecycle {
    precondition {
      condition     = data.external.check_integration_exists.result.exists == "true"
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                    COST COLLECTION TIMING ERROR                            ║
        ╠════════════════════════════════════════════════════════════════════════════╣
        ║ Cost collection cannot be enabled during initial integration creation.    ║
        ║                                                                            ║
        ║ This is a known limitation - cost collection must be enabled after the    ║
        ║ integration is created.                                                   ║
        ║                                                                            ║
        ║ To proceed:                                                               ║
        ║   1. Set cost_collection_enabled = false                                  ║
        ║   2. Run terraform apply to create the integration                        ║
        ║   3. Set cost_collection_enabled = true                                   ║
        ║   4. Run terraform apply again to enable cost collection                  ║
        ╚════════════════════════════════════════════════════════════════════════════╝
      EOF
    }
  }
}

# Marker resource to indicate all prechecks have passed
# Other resources can depend on this instead of null_resource.precheck_marker
resource "terraform_data" "prechecks_complete" {
  depends_on = [
    terraform_data.validate_home_region,
    terraform_data.validate_home_region_support,
    terraform_data.validate_user_group_consistency,
    terraform_data.validate_vault_quota,
    terraform_data.validate_connector_hub_quota,
    terraform_data.validate_enabled_regions,
    terraform_data.validate_enabled_regions_have_subnets,
    terraform_data.validate_parent_compartment_immutability,
    terraform_data.validate_infrastructure_regions_removal,
    terraform_data.validate_compartment_immutability,
    terraform_data.validate_user_group_immutability,
    terraform_data.validate_cost_collection_timing,
  ]
}

