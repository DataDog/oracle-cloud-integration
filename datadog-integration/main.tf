module "compartment" {
  source                = "./modules/compartment"
  compartment_name      = local.compartment_name
  parent_compartment_id = var.tenancy_ocid
  tags                  = local.tags
}

module "kms" {
  source          = "./modules/kms"
  count           = var.region == local.home_region_name ? 1 : 0
  compartment_id  = module.compartment.id
  datadog_api_key = var.datadog_api_key
  tags            = local.tags
}

module "auth" {
  source           = "./modules/auth"
  count            = var.region == local.home_region_name ? 1 : 0
  user_name        = local.user_name
  tenancy_id       = var.tenancy_ocid
  tags             = local.tags
  current_user_id  = var.current_user_ocid
  compartment_name = local.compartment_name
  compartment_id   = module.compartment.id
}

module "integration" {
  depends_on = [module.kms]
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
  private_key                     = module.auth[0].private_key
  public_key_finger_print         = module.auth[0].public_key_fingerprint
  user_ocid                       = module.auth[0].user_id
  subscribed_regions              = local.subscribed_regions_list
  datadog_resource_compartment_id = module.compartment.id
}

resource "terraform_data" "regional_stack_zip" {
  provisioner "local-exec" {
    working_dir = "${path.module}/modules/regional-stacks"
    command     = "rm dd_regional_stack.zip;zip -r dd_regional_stack.zip ./*.tf"
  }
  triggers_replace = {
    "key" = timestamp()
  }
}

resource "terraform_data" "regional_stacks_create_apply" {
  depends_on = [terraform_data.regional_stack_zip]
  input = {
    compartment = module.compartment.id
  }
  for_each = local.subscribed_regions_set
  provisioner "local-exec" {
    working_dir = path.module
    when        = create
    command     = <<EOT

    echo "Checking any existing stacks in the compartment and destroy them...."

    chmod +x ${path.module}/delete_stack.sh; ${path.module}/delete_stack.sh ${self.input.compartment} ${each.key}

    STACK_ID=$(oci resource-manager stack create --compartment-id ${self.input.compartment} --display-name datadog-regional-stack-${each.key} \
      --config-source ${path.module}/modules/regional-stacks/dd_regional_stack.zip  --variables '{"tenancy_ocid": "${var.tenancy_ocid}", "region": "${each.key}", \
      "compartment_ocid": "${self.input.compartment}", "datadog_site": "${var.datadog_site}", "api_key_secret_id": "${module.kms[0].api_key_secret_id}", \
      "home_region": "${local.home_region_name}", "region_key": "${local.subscribed_regions_map[each.key].region_key}"}' \
      --query "data.id" --raw-output --region ${each.key})
    
    echo "Created Stack ID: $STACK_ID in region ${each.key}"

    # Create and wait for apply job
    
    echo "Apply Job for stack: $STACK_ID in region ${each.key}"
    JOB_ID=$(oci resource-manager job create-apply-job --stack-id $STACK_ID --wait-for-state SUCCEEDED --wait-for-state FAILED --execution-plan-strategy AUTO_APPROVED --region ${each.key} --query "data.id")

    EOT
  }

  provisioner "local-exec" {
    working_dir = path.module
    when        = destroy
    command     = <<EOT
    echo "Destroying........."
    chmod +x ${path.module}/delete_stack.sh && ${path.module}/delete_stack.sh ${self.input.compartment} ${each.key}
    
    EOT
  }
}

