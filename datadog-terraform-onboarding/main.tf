# Validate user and group configurations
resource "null_resource" "user_group_validation" {
  
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command = <<-EOT
      # Check existing_user_id format if provided
      if [ "${var.existing_user_id != null ? var.existing_user_id : ""}" != "" ]; then
        if ! echo "${var.existing_user_id != null ? var.existing_user_id : ""}" | grep -q "^ocid1\\.user\\.oc[0-9]\\."; then
          echo "ERROR: Invalid existing_user_id format."
          echo "If provided, existing_user_id must be a valid user OCID starting with: ocid1.user.oc[0-9]."
          echo "Provided value: '${var.existing_user_id != null ? var.existing_user_id : "null"}'"
          exit 1
        fi
      fi
      
      # Check existing_group_id format if provided
      if [ "${var.existing_group_id != null ? var.existing_group_id : ""}" != "" ]; then
        if ! echo "${var.existing_group_id != null ? var.existing_group_id : ""}" | grep -q "^ocid1\\.group\\.oc[0-9]\\."; then
          echo "ERROR: Invalid existing_group_id format."
          echo "If provided, existing_group_id must be a valid group OCID starting with: ocid1.group.oc[0-9]."
          echo "Provided value: '${var.existing_group_id != null ? var.existing_group_id : "null"}'"
          exit 1
        fi
      fi
      
      # Check that existing_user_id and existing_group_id are both null or both provided
      USER_IS_NULL="${var.existing_user_id == null ? "true" : "false"}"
      GROUP_IS_NULL="${var.existing_group_id == null ? "true" : "false"}"
      
      if [ "$USER_IS_NULL" != "$GROUP_IS_NULL" ]; then
        echo "ERROR: existing_user_id and existing_group_id must be either both null or both provided."
        echo "Provided: existing_user_id = '${var.existing_user_id != null ? var.existing_user_id : "null"}', existing_group_id = '${var.existing_group_id != null ? var.existing_group_id : "null"}'"
        exit 1
      fi
      
      echo "✅ User and group validation passed"
    EOT
  }

  triggers = {
    existing_user_id = var.existing_user_id != null ? var.existing_user_id : "null"
    existing_group_id = var.existing_group_id != null ? var.existing_group_id : "null"
  }
}

# Validate subnet regions and fail if any unknown regions detected
resource "null_resource" "subnet_region_validation" {
  depends_on = [null_resource.user_group_validation]
  
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command = <<-EOT
      # First check OCID structure validity
      INVALID_OCIDS="${join(" ", local.invalid_structure_ocids)}"
      if [ ! -z "$INVALID_OCIDS" ] && [ ${length(local.subnet_ocids_list)} -gt 0 ]; then
        echo "ERROR: Invalid subnet OCID structure detected:"
        echo "${join("\n", local.invalid_structure_ocids)}"
        echo ""
        echo "All subnet OCIDs must have exactly 5 dot-separated parts (format: ocid1.subnet.oc1.<region>.<unique_id>)."
        echo "Note: Make sure you are providing subnet OCIDs (ocid1.subnet.oc1...) not VCN OCIDs or other resource types."
        exit 1
      fi
      
      # Check for duplicate OCIDs
      DUPLICATE_OCIDS="${join(" ", distinct(local.duplicate_ocids))}"
      if [ ! -z "$DUPLICATE_OCIDS" ] && [ ${length(local.subnet_ocids_list)} -gt 0 ]; then
        echo "ERROR: Duplicate subnet OCIDs found:"
        echo "${join("\n", distinct(local.duplicate_ocids))}"
        echo ""
        echo "All subnet OCIDs must be unique."
        exit 1
      fi
      
      # Check for duplicate regions
      DUPLICATE_REGIONS="${join(" ", distinct(local.duplicate_regions))}"
      if [ ! -z "$DUPLICATE_REGIONS" ] && [ ${length(local.subnet_ocids_list)} -gt 0 ]; then
        echo "ERROR: Multiple subnet OCIDs found in the same region for:"
        echo "${join("\n", distinct(local.duplicate_regions))}"
        echo ""
        echo "Each region can only have one subnet OCID."
        exit 1
      fi
      
      # Check for unknown regions
      UNKNOWN_REGIONS="${join(" ", [for region in local.subnet_regions : region if substr(region, 0, 15) == "unknown-region-"])}"
      if [ ! -z "$UNKNOWN_REGIONS" ]; then
        echo "ERROR: The following subnet regions are not subscribed in this tenancy: $UNKNOWN_REGIONS"
        echo ""
        echo "This usually means the region in the subnet OCID is not subscribed in this tenancy or the region code format is not recognized."
        echo ""
        echo "Subscribed regions: ${join(", ", sort(local.subscribed_regions_list))}"
        echo "Region mapping: ${jsonencode(local.region_key_to_name_map)}"
        echo ""
        echo "Please verify your subnet OCIDs are correct and from subscribed regions."
        exit 1
      fi
      echo "✅ All subnet OCIDs are valid and all subnet regions are subscribed"
    EOT
  }

  triggers = {
    subnet_regions = jsonencode(local.subnet_regions)
    invalid_ocids = jsonencode(local.invalid_structure_ocids)
    duplicate_ocids = jsonencode(local.duplicate_ocids)
    duplicate_regions = jsonencode(local.duplicate_regions)
  }
}

# Output region intersection logic and validate region consistency
resource "null_resource" "region_intersection_info" {
  depends_on = [null_resource.subnet_region_validation,data.external.supported_regions]
  
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command = <<-EOT
      echo "==================== DATADOG REGIONAL STACK DEPLOYMENT INFO ===================="
      echo "Subscribed regions in tenancy: ${join(", ", sort(tolist(local.subscribed_regions_set)))}"
      echo "Regions available in identity domain: ${join(", ", sort(tolist(local.regions_in_domain_set)))}"
      echo "Regions with provided subnet OCIDs: ${length(local.subnet_ocids_list) > 0 ? join(", ", sort(tolist(local.subnet_regions))) : "None (will create subnets in all subscribed regions)"}"
      echo "Regions where Docker image is available: ${join(", ", sort(tolist(local.docker_image_enabled_regions)))}"
      echo "Target regions for regional stack deployment: ${join(", ", sort(tolist(local.target_regions_for_stacks)))}"
      echo "Number of regional stacks to be created: ${length(local.target_regions_for_stacks)}"
      echo "================================================================================="
      
      # Check for region consistency between subscribed regions and domain regions
      SUBSCRIBED_MINUS_DOMAIN="${join(" ", [for r in local.subscribed_regions_set : r if !contains(tolist(local.regions_in_domain_set), r)])}"
      DOMAIN_MINUS_SUBSCRIBED="${join(" ", [for r in local.regions_in_domain_set : r if !contains(tolist(local.subscribed_regions_set), r)])}"
      
      if [ ! -z "$SUBSCRIBED_MINUS_DOMAIN" ] || [ ! -z "$DOMAIN_MINUS_SUBSCRIBED" ]; then
        echo ""
        echo "WARNING: Subscribed regions do not match regions in domain."
        echo "This indicates a configuration mismatch between the tenancy's subscribed regions and the identity domain's available regions."
        echo ""
        echo "Subscribed regions: ${join(", ", sort(tolist(local.subscribed_regions_set)))}"
        echo "Regions in domain: ${join(", ", sort(tolist(local.regions_in_domain_set)))}"
      fi
      
      # Check if any regional stacks will be created
      if [ ${length(local.target_regions_for_stacks)} -eq 0 ]; then
        echo ""
        echo "ERROR: No regional stacks will be created!"
        echo ""
        echo "This usually happens when:"
        echo "- Provided subnet OCIDs don't match any subscribed regions"
        echo "- Provided subnet OCIDs don't match regions available in the identity domain"
        echo "- All provided subnet regions are invalid or unsupported"
        echo ""
        echo "Please check your subnet OCIDs and ensure they belong to regions that are:"
        echo "1. Subscribed in this tenancy"
        echo "2. Available in the identity domain"
        echo "3. Supported by Datadog"
        exit 1
      fi
      
      echo "✅ Region validation passed - proceeding with deployment"
    EOT
  }

  triggers = {
    region_validation = jsonencode({
      subscribed_regions = local.subscribed_regions_set
      domain_regions = local.regions_in_domain_set
      target_regions = local.target_regions_for_stacks
    })
  }
}

# Prechecks are now defined in prechecks.tf using native Terraform data sources
# This replaces the old pre_check.py script that required OCI CLI

module "compartment" {
  depends_on            = [terraform_data.prechecks_complete]
  source                = "./modules/compartment"
  compartment_id        = var.compartment_id
  new_compartment_name  = local.new_compartment_name
  parent_compartment_id = var.tenancy_ocid
  tags                  = local.tags
}

module "kms" {
  depends_on      = [terraform_data.prechecks_complete]
  source          = "./modules/kms"
  count           = (local.is_current_region_home_region && var.enable_vault) ? 1 : 0
  compartment_id  = module.compartment.id
  datadog_api_key = var.datadog_api_key
  tags            = local.tags
}

module "auth" {
  depends_on        = [terraform_data.prechecks_complete]
  source            = "./modules/auth"
  count             = local.is_current_region_home_region ? 1 : 0
  user_name         = local.actual_user_name
  user_email        = local.user_email
  tenancy_id        = var.tenancy_ocid
  tags              = local.tags
  current_user_id   = var.current_user_ocid
  compartment_id    = module.compartment.id
  idcs_endpoint     = local.idcs_endpoint
  existing_user_id  = var.existing_user_id
  existing_group_id = var.existing_group_id
  user_group_name   = local.actual_group_name
  user_policy_name  = local.user_group_policy_name
  dg_sch_name       = local.dg_sch_name
  dg_fn_name        = local.dg_fn_name
  dg_policy_name    = local.dg_policy_name
}

module "key" {
  source           = "./modules/key"
  count            = local.is_current_region_home_region ? 1 : 0
  existing_user_id = module.auth[0].user_id
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = module.compartment.id
  region           = var.region
  idcs_endpoint    = local.idcs_endpoint
  tags             = local.tags
  depends_on       = [terraform_data.prechecks_complete, module.auth]
}

module "integration" {
  depends_on = [terraform_data.prechecks_complete, module.auth, module.key, module.kms]
  source     = "./modules/integration"
  providers = {
    restapi = restapi
  }
  count                           = local.is_current_region_home_region ? 1 : 0
  datadog_api_key                 = var.datadog_api_key
  datadog_app_key                 = var.datadog_app_key
  datadog_site                    = var.datadog_site
  home_region                     = local.home_region_name
  tenancy_ocid                    = var.tenancy_ocid
  private_key                     = module.key[0].private_key
  user_ocid                       = module.auth[0].user_id
  subscribed_regions              = tolist(local.final_regions_for_stacks)
  datadog_resource_compartment_id = module.compartment.id
  logs_enabled                    = var.logs_enabled
  metrics_enabled                 = var.metrics_enabled
  resources_enabled               = var.resources_enabled
  cost_collection_enabled         = var.cost_collection_enabled
  enabled_regions                 = var.enabled_regions
  logs_enabled_services           = var.logs_enabled_services
  logs_compartment_tag_filters    = var.logs_compartment_tag_filters
  metrics_enabled_services        = var.metrics_enabled_services
  metrics_compartment_tag_filters = var.metrics_compartment_tag_filters
}


