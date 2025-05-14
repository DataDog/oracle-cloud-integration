#!/bin/bash

COMPARTMENT=$1
REGION=$2
DISPLAY_NAME=$3

STACK_IDS=($(oci --region "$REGION" resource-manager stack list --compartment-id $COMPARTMENT --display-name $DISPLAY_NAME --raw-output | jq -r '.data[]."id"'))

if [[ -z "$STACK_IDS" ]]; then
  echo "No stacks found in the compartment."
  exit 0
fi

echo "Found... stack... Ids: ${STACK_IDS[@]}"
for STACK_ID in "${STACK_IDS[@]}"; do
  echo "Running...destroy...job...for...stack...: $STACK_ID"

  JOB_ID=$(oci --region "$REGION" resource-manager job create-destroy-job \
    --stack-id "$STACK_ID" --wait-for-state SUCCEEDED --wait-for-state FAILED \
    --execution-plan-strategy AUTO_APPROVED \
    --query "data.id" --raw-output)
  
  if [[ -z "$JOB_ID" ]]; then
    echo "Destroy job not successfully completed."
    exit 1
  fi

  echo "Waiting....for.....destroy....job....($JOB_ID)....to....complete..."

  echo "Deleting....stack: $STACK_ID"
  oci --region "$REGION" resource-manager stack delete --stack-id "$STACK_ID" --force
done

echo "All stacks destroyed for the region: $REGION."