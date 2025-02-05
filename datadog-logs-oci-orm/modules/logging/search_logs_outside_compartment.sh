#!/bin/bash

export LOG_GROUP_IDS="${1}"
export RESOURCE_ID="${2}"
export HAS_LOGGROUP="${3}"
if [ "$HAS_LOGGROUP" = "Y" ]; then
    echo "{\"content\": \"\"}"
    exit 0
fi

IFS=',' read -ra types <<< "$LOG_GROUP_IDS"
found=false
for lgid in "${types[@]}"; do
    response=$(oci logging log list --log-group-id $lgid \
        --query "data[?configuration.source.resource=='${RESOURCE_ID}']" \
        --output json)

    if [[ $(echo "$response" | jq 'length') -ne 0 ]]; then
        output_file="${RESOURCE_ID}.json"
        echo "[]" > $output_file # Initialize the output file with an empty JSON array
        loggroup=$(echo "$response" | jq -c '.[0] | {log_group_id: .["log-group-id"], state: .["lifecycle-state"], is_enabled: .["is-enabled"], compartment_id: .["compartment-id"]}')
        # Write the response to the output file
        echo "$loggroup" > "$output_file"
        found=true
        break
    fi
done
if [ "$found" = false ]; then
    echo "{\"content\": \"\"}"
else
    # Output the response in a valid JSON map for Terraform's external data source
    content=$(jq -c . < "$output_file") # Ensure the file's content is compact JSON
    rm -f "$output_file"
    echo "{\"content\": \"$(echo "$content" | sed 's/"/\\"/g')\"}" # Escape quotes for JSON compatibility
fi
