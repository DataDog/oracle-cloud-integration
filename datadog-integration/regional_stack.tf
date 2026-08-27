
resource "terraform_data" "regional_stack_zip" {
  depends_on = [null_resource.precheck_marker]
  provisioner "local-exec" {
    working_dir = "${path.module}/modules/regional-stacks"
    command     = "rm -f dd_regional_stack.zip && zip -r dd_regional_stack.zip ./*.tf"
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
resource "null_resource" "regional_stacks_create_apply_parallel" {
  depends_on = [null_resource.precheck_marker, null_resource.region_intersection_info, terraform_data.regional_stack_zip, terraform_data.stack_digest, module.compartment, module.auth, module.kms]
  for_each   = var.apply_regional_stacks_sequentially ? toset([]) : local.target_regions_for_stacks

  provisioner "local-exec" {
    working_dir = path.module
    command     = "bash ./create_apply_regional_stack.sh '${each.key}' '${local.supported_regions[each.key].result.failure}' '${local.subscribed_regions_map[each.key].region_key}' '${lookup(local.region_to_subnet_ocid_map, each.key, "")}' '${module.compartment.id}' '${terraform_data.stack_digest.id}' '${var.tenancy_ocid}' '${var.datadog_site}' '${module.kms[0].api_key_secret_id}' '${local.home_region_name}' '${jsonencode(local.defined_tags)}' '${var.enable_regional_vaults}' '${jsonencode(local.compartment_defined_tags)}'"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "regional_stacks_create_apply_sequential" {
  count      = var.apply_regional_stacks_sequentially ? 1 : 0
  depends_on = [null_resource.precheck_marker, null_resource.region_intersection_info, terraform_data.regional_stack_zip, terraform_data.stack_digest, module.compartment, module.auth, module.kms]

  provisioner "local-exec" {
    working_dir = path.module
    command = <<EOT
    REGIONS_JSON='${jsonencode({ for region in local.target_regions_for_stacks : region => {
    failure     = local.supported_regions[region].result.failure
    region_key  = local.subscribed_regions_map[region].region_key
    subnet_ocid = lookup(local.region_to_subnet_ocid_map, region, "")
} })}'

    for REGION in ${join(" ", sort(tolist(local.target_regions_for_stacks)))}; do
      FAILURE=$(echo "$REGIONS_JSON" | jq -r --arg region "$REGION" '.[$region].failure')
      REGION_KEY=$(echo "$REGIONS_JSON" | jq -r --arg region "$REGION" '.[$region].region_key')
      SUBNET_OCID=$(echo "$REGIONS_JSON" | jq -r --arg region "$REGION" '.[$region].subnet_ocid')
      bash ./create_apply_regional_stack.sh "$REGION" "$FAILURE" "$REGION_KEY" "$SUBNET_OCID" '${module.compartment.id}' '${terraform_data.stack_digest.id}' '${var.tenancy_ocid}' '${var.datadog_site}' '${module.kms[0].api_key_secret_id}' '${local.home_region_name}' '${jsonencode(local.defined_tags)}' '${var.enable_regional_vaults}' '${jsonencode(local.compartment_defined_tags)}' || { echo "ERROR: regional stack apply failed for region $REGION; aborting sequential apply." >&2; exit 1; }
    done
    EOT
}

triggers = {
  always_run = timestamp()
}
}

# Using terraform_data only for destroy because other resource data or local variables cannot be referenced in destroy block. terraform_data allows that to refer from the self reference which is not
# present in null_resource. This is not used during create because terraform_data is destroyed on trigger.
resource "terraform_data" "regional_stacks_destroy" {
  depends_on = [null_resource.precheck_marker, terraform_data.regional_stack_zip, terraform_data.stack_digest, module.kms]
  for_each   = local.target_regions_for_stacks
  input = {
    compartment       = module.compartment.id
    stack_digest_id   = terraform_data.stack_digest.id
    defined_tags_json = length(keys(local.compartment_defined_tags)) > 0 ? jsonencode(local.compartment_defined_tags) : ""
  }

  provisioner "local-exec" {
    working_dir = path.module
    when        = destroy
    command     = <<EOT
    echo "Destroying........."
    STACK_NAME="datadog-regional-stack-${self.input.stack_digest_id}"
    DEFINED_TAGS_JSON="${replace(replace(try(self.input.defined_tags_json, ""), "$", "\\$"), "\"", "\\\"")}"
    chmod +x ${path.module}/delete_stack.sh && ${path.module}/delete_stack.sh ${self.input.compartment} ${each.key} "$STACK_NAME" "$DEFINED_TAGS_JSON"
    EOT
  }
}
