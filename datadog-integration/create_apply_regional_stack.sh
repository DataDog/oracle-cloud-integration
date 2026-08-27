#!/bin/bash

set -e

REGION="$1"
FAILURE="$2"
REGION_KEY="$3"
SUBNET_OCID="$4"
COMPARTMENT_ID="$5"
STACK_DIGEST_ID="$6"
TENANCY_OCID="$7"
DATADOG_SITE="$8"
API_KEY_SECRET_ID="$9"
HOME_REGION="${10}"
DEFINED_TAGS="${11}"
ENABLE_REGIONAL_VAULTS="${12}"
DEFINED_TAGS_FLAG="${13}"

export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True

echo "Checking if the region $REGION is supported or not"
if [[ "$FAILURE" != "" ]]; then
  echo "The region $REGION is not supported.....exit"
  exit 0
fi

echo "Checking any existing stacks in the compartment...."
STACK_NAME="datadog-regional-stack-$STACK_DIGEST_ID"
STACK_IDS=($(oci --region "$REGION" resource-manager stack list --display-name "$STACK_NAME" --compartment-id "$COMPARTMENT_ID" --raw-output | jq -r '.data[]."id"'))
STACK_ID=''
VARIABLES_JSON=$(jq -n \
  --arg tenancy_ocid "$TENANCY_OCID" \
  --arg region "$REGION" \
  --arg compartment_ocid "$COMPARTMENT_ID" \
  --arg datadog_site "$DATADOG_SITE" \
  --arg api_key_secret_id "$API_KEY_SECRET_ID" \
  --arg home_region "$HOME_REGION" \
  --arg region_key "$REGION_KEY" \
  --arg subnet_ocid "$SUBNET_OCID" \
  --arg defined_tags "$DEFINED_TAGS" \
  --arg enable_regional_vaults "$ENABLE_REGIONAL_VAULTS" \
  '{tenancy_ocid: $tenancy_ocid, region: $region, compartment_ocid: $compartment_ocid, datadog_site: $datadog_site, api_key_secret_id: $api_key_secret_id, home_region: $home_region, region_key: $region_key, subnet_ocid: $subnet_ocid, defined_tags: $defined_tags, enable_regional_vaults: $enable_regional_vaults}')

if [[ -z "$STACK_IDS" ]]; then
  echo "No stack found in the compartment by the name $STACK_NAME in region $REGION. Creating..."
  STACK_ID=$(oci resource-manager stack create --compartment-id "$COMPARTMENT_ID" --display-name "$STACK_NAME" \
    --config-source ./modules/regional-stacks/dd_regional_stack.zip --variables "$VARIABLES_JSON" \
    --terraform-version 1.5.x \
    $DEFINED_TAGS_FLAG \
    --wait-for-state ACTIVE \
    --max-wait-seconds 120 \
    --wait-interval-seconds 5 \
    --query "data.id" --raw-output --region "$REGION")
  echo "Created Stack ID: $STACK_ID in region $REGION"
else
  echo "Found stacks..... ${STACK_IDS[@]}"
  STACK_ID="${STACK_IDS[0]}"
  echo "Refreshing config source and variables for existing stack $STACK_ID in region $REGION..."
  if ! UPDATE_OUTPUT=$(oci resource-manager stack update --stack-id "$STACK_ID" --force \
    --config-source ./modules/regional-stacks/dd_regional_stack.zip --variables "$VARIABLES_JSON" \
    --terraform-version 1.5.x \
    $DEFINED_TAGS_FLAG \
    --region "$REGION" 2>&1); then
    echo "ERROR: Failed to update stack $STACK_ID in region $REGION: $UPDATE_OUTPUT"
    exit 1
  fi
fi

echo "Apply Job for stack: $STACK_ID in region $REGION"
JOB_JSON=""
for attempt in {1..5}; do
  echo "Attempting to create job (attempt $attempt/5)..."
  if JOB_JSON=$(oci resource-manager job create-apply-job \
    --stack-id "$STACK_ID" $DEFINED_TAGS_FLAG \
    --wait-for-state SUCCEEDED --wait-for-state FAILED \
    --execution-plan-strategy AUTO_APPROVED \
    --region "$REGION" \
    --query 'data.{id:id,state:"lifecycle-state"}'); then
    break
  fi

  echo "Job creation failed on attempt $attempt"
  if [ "$attempt" -lt 5 ]; then
    echo "Waiting 6 seconds before retry..."
    sleep 6
  fi
done

JOB_ID=$(echo "$JOB_JSON" | jq -r '.id')
JOB_STATE=$(echo "$JOB_JSON" | jq -r '.state')

if [[ -z "$JOB_ID" || "$JOB_ID" == "null" ]]; then
  echo "ERROR: Failed to create apply job after 5 attempts for region $REGION."
  exit 1
fi

echo "Apply job ($JOB_ID) for region $REGION finished with state $JOB_STATE"
if [[ "$JOB_STATE" != "SUCCEEDED" ]]; then
  echo "ERROR: Apply job $JOB_ID did not succeed (state: $JOB_STATE) for region $REGION."
  exit 1
fi
