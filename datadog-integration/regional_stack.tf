# Validation check to ensure subscribed regions match regions in domain
check "regions_consistency" {
  assert {
    condition     = length(setsubtract(local.subscribed_regions_set, local.regions_in_domain_set)) == 0 && length(setsubtract(local.regions_in_domain_set, local.subscribed_regions_set)) == 0
    error_message = "Subscribed regions (${join(", ", sort(tolist(local.subscribed_regions_set)))}) do not match regions in domain (${join(", ", sort(tolist(local.regions_in_domain_set)))}). This indicates a configuration mismatch between the tenancy's subscribed regions and the identity domain's available regions."
  }
}

resource "terraform_data" "regional_stack_zip" {
  depends_on = [null_resource.precheck_marker]
  provisioner "local-exec" {
    working_dir = "${path.module}/modules/regional-stacks"
    command     = "rm dd_regional_stack.zip;zip -r dd_regional_stack.zip ./*.tf"
  }
  triggers_replace = {
    "key" = timestamp()
  }
}

# A dummy resource unique to the current stack. All the regional stacks are created with this id in their names.
resource "terraform_data" "stack_digest" {
  depends_on = [null_resource.precheck_marker]
  provisioner "local-exec" {
    working_dir = path.module
    command     = "echo $JOB_ID"
  }
}


# Using a null resource because we want this to be applied on every execution.
resource "null_resource" "regional_stacks_create_apply" {
  depends_on = [terraform_data.regional_stack_zip, terraform_data.stack_digest]
  # Not using local.supported_region_set here because that is determined during apply time and terraform needs to be aware of exact length during plan stage
  for_each = local.subscribed_regions_set
  provisioner "local-exec" {
    working_dir = path.module
    command     = <<EOT

    echo "Checking if the region ${each.key} is supported or not"
    VALUE="${local.supported_regions[each.key].result.failure}"
    CURRENT_REGION="${each.key}"

    
    if [[ "$VALUE" != "" ]]; then
      echo "The region ${each.key} is not supported.....exit"
      exit 0
    fi

    # Do not wait for the stack to be applied except for home region
    WAIT_COMMAND=""
    if [[ "$CURRENT_REGION" == "${local.home_region_name}" ]]; then
      WAIT_COMMAND="--wait-for-state SUCCEEDED --wait-for-state FAILED"
    fi

    echo "Checking any existing stacks in the compartment...."
    
    # The name of the stack to be created. Combined with the stack_digest to make it unique to this stack
    STACK_NAME="datadog-regional-stack-${terraform_data.stack_digest.id}"

    # Fetching the existing regional stacks associated with this parent stack
    STACK_IDS=($(oci --region ${each.key} resource-manager stack list --display-name $STACK_NAME --compartment-id ${module.compartment.id} --raw-output | jq -r '.data[]."id"'))
    STACK_ID=''
    
    if [[ -z "$STACK_IDS" ]]; then
      echo "No stack found in the compartment by the name $STACK_NAME in region ${each.key}. Creating..."
      STACK_ID=$(oci resource-manager stack create --compartment-id ${module.compartment.id} --display-name $STACK_NAME \
      --config-source ${path.module}/modules/regional-stacks/dd_regional_stack.zip  --variables '{"tenancy_ocid": "${var.tenancy_ocid}", "region": "${each.key}", \
      "compartment_ocid": "${module.compartment.id}", "datadog_site": "${var.datadog_site}", "api_key_secret_id": "${module.kms[0].api_key_secret_id}", \
      "home_region": "${local.home_region_name}", "region_key": "${local.subscribed_regions_map[each.key].region_key}", \
      "subnet_partial_name": "${var.vcn_search_string}"}' \
      --query "data.id" --raw-output --region ${each.key})
      echo "Created Stack ID: $STACK_ID in region ${each.key}"
    else
      echo "Found stacks..... $${STACK_IDS[@]}"
      STACK_ID="$${STACK_IDS[@]:0:1}"
    fi
  

    # Create and wait for apply job
    
    echo "Apply Job for stack: $STACK_ID in region ${each.key}"
    JOB_ID=$(oci resource-manager job create-apply-job --stack-id $STACK_ID $WAIT_COMMAND --execution-plan-strategy AUTO_APPROVED --region ${each.key} --query "data.id")

    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

# Using terraform_data only for destroy because other resource data or local variables cannot be referenced in destroy block. terraform_data allows that to refer from the self reference which is not 
# present in null_resource. This is not used during create because terraform_data is destroyed on trigger.
resource "terraform_data" "regional_stacks_destroy" {
  depends_on = [terraform_data.regional_stack_zip, terraform_data.stack_digest]
  for_each   = local.subscribed_regions_set
  input = {
    compartment     = module.compartment.id
    stack_digest_id = terraform_data.stack_digest.id
  }

  provisioner "local-exec" {
    working_dir = path.module
    when        = destroy
    command     = <<EOT
    echo "Destroying........."
    STACK_NAME="datadog-regional-stack-${self.input.stack_digest_id}"
    chmod +x ${path.module}/delete_stack.sh && ${path.module}/delete_stack.sh ${self.input.compartment} ${each.key} $STACK_NAME
    
    EOT
  }
}
