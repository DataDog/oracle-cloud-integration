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

# Check 11: Prevent cost collection at initial creation
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
    terraform_data.validate_cost_collection_timing,
  ]
}

