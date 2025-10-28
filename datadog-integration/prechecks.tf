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

# Data source: Check if user already exists (by name)
# Note: OCI Identity Domains data sources retrieve all resources, we filter in Terraform
data "oci_identity_domains_users" "existing_user_check" {
  count         = var.existing_user_id == null ? 1 : 0
  idcs_endpoint = local.idcs_endpoint
}

# Check 3: Validate user doesn't already exist
resource "terraform_data" "validate_user_not_exists" {
  count = var.existing_user_id == null ? 1 : 0
  
  lifecycle {
    precondition {
      condition = length([
        for user in data.oci_identity_domains_users.existing_user_check[0].users :
        user if try(user.user_name, user.name, "") == local.actual_user_name
      ]) == 0
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                      RESOURCE ALREADY EXISTS ERROR                         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        User "${local.actual_user_name}" already exists in the identity domain.
        
        Options:
        1. Use existing user: Set existing_user_id and existing_group_id variables
        2. Choose different name: Set datadog_user_name variable to a unique name
        3. Delete existing: Remove the user from OCI Console first
      EOF
    }
  }
}

# Data source: Check if group already exists (by name)
data "oci_identity_domains_groups" "existing_group_check" {
  count         = var.existing_group_id == null ? 1 : 0
  idcs_endpoint = local.idcs_endpoint
}

# Check 4: Validate group doesn't already exist
resource "terraform_data" "validate_group_not_exists" {
  count = var.existing_group_id == null ? 1 : 0
  
  lifecycle {
    precondition {
      condition = length([
        for group in data.oci_identity_domains_groups.existing_group_check[0].groups :
        group if try(group.display_name, "") == local.actual_group_name
      ]) == 0
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                      RESOURCE ALREADY EXISTS ERROR                         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        Group "${local.actual_group_name}" already exists in the identity domain.
        
        Options:
        1. Use existing group: Set existing_user_id and existing_group_id variables
        2. Choose different name: Set datadog_user_group_name variable
        3. Delete existing: Remove the group from OCI Console first
      EOF
    }
  }
}

# Data source: Check if user group policy already exists
data "oci_identity_policies" "existing_user_policy_check" {
  compartment_id = var.tenancy_ocid
  
  filter {
    name   = "name"
    values = [local.user_group_policy_name]
  }
}

# Check 5: Validate user group policy doesn't already exist
resource "terraform_data" "validate_user_policy_not_exists" {
  lifecycle {
    precondition {
      condition     = length(data.oci_identity_policies.existing_user_policy_check.policies) == 0
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                      RESOURCE ALREADY EXISTS ERROR                         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        Policy "${local.user_group_policy_name}" already exists.
        
        This may be from a previous deployment. Please delete it from:
        Identity & Security → Policies → ${local.user_group_policy_name}
      EOF
    }
  }
}

# Data source: Check if dynamic group (SCH) already exists
data "oci_identity_domains_dynamic_resource_groups" "existing_dg_sch_check" {
  idcs_endpoint = local.idcs_endpoint
}

# Check 6: Validate dynamic group (SCH) doesn't already exist
resource "terraform_data" "validate_dg_sch_not_exists" {
  lifecycle {
    precondition {
      condition = length([
        for dg in data.oci_identity_domains_dynamic_resource_groups.existing_dg_sch_check.dynamic_resource_groups :
        dg if try(dg.display_name, "") == local.dg_sch_name
      ]) == 0
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                      RESOURCE ALREADY EXISTS ERROR                         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        Dynamic Group "${local.dg_sch_name}" already exists.
        
        This may be from a previous deployment. Please delete it from:
        Identity & Security → Domains → Dynamic Groups → ${local.dg_sch_name}
      EOF
    }
  }
}

# Data source: Check if dynamic group (Functions) already exists
data "oci_identity_domains_dynamic_resource_groups" "existing_dg_fn_check" {
  idcs_endpoint = local.idcs_endpoint
}

# Check 7: Validate dynamic group (Functions) doesn't already exist
resource "terraform_data" "validate_dg_fn_not_exists" {
  lifecycle {
    precondition {
      condition = length([
        for dg in data.oci_identity_domains_dynamic_resource_groups.existing_dg_fn_check.dynamic_resource_groups :
        dg if try(dg.display_name, "") == local.dg_fn_name
      ]) == 0
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                      RESOURCE ALREADY EXISTS ERROR                         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        Dynamic Group "${local.dg_fn_name}" already exists.
        
        This may be from a previous deployment. Please delete it from:
        Identity & Security → Domains → Dynamic Groups → ${local.dg_fn_name}
      EOF
    }
  }
}

# Data source: Check if dynamic group policy already exists
data "oci_identity_policies" "existing_dg_policy_check" {
  compartment_id = var.tenancy_ocid
  
  filter {
    name   = "name"
    values = [local.dg_policy_name]
  }
}

# Check 8: Validate dynamic group policy doesn't already exist
resource "terraform_data" "validate_dg_policy_not_exists" {
  lifecycle {
    precondition {
      condition     = length(data.oci_identity_policies.existing_dg_policy_check.policies) == 0
      error_message = <<-EOF
        ╔════════════════════════════════════════════════════════════════════════════╗
        ║                      RESOURCE ALREADY EXISTS ERROR                         ║
        ╚════════════════════════════════════════════════════════════════════════════╝
        
        Policy "${local.dg_policy_name}" already exists.
        
        This may be from a previous deployment. Please delete it from:
        Identity & Security → Policies → ${local.dg_policy_name}
      EOF
    }
  }
}

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

# Marker resource to indicate all prechecks have passed
# Other resources can depend on this instead of null_resource.precheck_marker
resource "terraform_data" "prechecks_complete" {
  depends_on = [
    terraform_data.validate_home_region,
    terraform_data.validate_home_region_support,
    terraform_data.validate_user_not_exists,
    terraform_data.validate_group_not_exists,
    terraform_data.validate_user_policy_not_exists,
    terraform_data.validate_dg_sch_not_exists,
    terraform_data.validate_dg_fn_not_exists,
    terraform_data.validate_dg_policy_not_exists,
    terraform_data.validate_vault_quota,
    terraform_data.validate_connector_hub_quota,
  ]
}

