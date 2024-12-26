#!/bin/bash
# Export exclude_services from Terraform variable
export RESOURCE_TYPES="${3}"
# Export compartment OCID from Terraform variable
export COMPARTMENT_ID="${1}"

export SERVICE_ID="${2}"

output_file="oci_resources_${SERVICE_ID}_${COMPARTMENT_ID}.json"
echo "[]" > $output_file # Initialize the output file with an empty JSON array
IFS=',' read -ra types <<< "$RESOURCE_TYPES"
# Perform OCI CLI query for each resource type
for rt in "${types[@]}"; do
    # Initialize variables for pagination
    next_page="init"

    # Loop through pages
    while [ "$next_page" != "null" ]; do
        if [ "$next_page" == "init" ]; then
            # First query without next page token
            response=$(oci search resource structured-search --query-text \
                "QUERY $rt resources where compartmentId = '$COMPARTMENT_ID' && lifeCycleState != 'TERMINATED' && lifeCycleState != 'FAILED'" \
                --output json)
        else
            # Query with next page token
            response=$(oci search resource structured-search --query-text \
                "QUERY $rt resources where compartmentId = '$COMPARTMENT_ID' && lifeCycleState != 'TERMINATED' && lifeCycleState != 'FAILED'" \
                --page "$next_page" \
                --output json)
        fi
        
        # Check if the response contains an error
        if [ -z "$response" ]; then
            # Log ServiceError responses
            echo "ServiceError for $SERVICE_ID, resource type: $rt" >> error.log
            break
        fi
        
        # Extract next page token
        next_page=$(echo "$response" | jq -r '."opc-next-page" // "null"')

        # Extract and transform items
        items=$(echo "$response" | jq --arg service_id "$SERVICE_ID" -c '[.data.items[] | {compartmentId: ."compartment-id", displayName: ."display-name", identifier: ."identifier", resourceType: ."resource-type", serviceId: $service_id}]')
        # Append items to the output file if not empty
        if [ "$(echo "$items" | jq length)" -gt 0 ]; then
            temp_items_file="temp_items_$${SERVICE_ID}_$${COMPARTMENT_ID}.json"
            echo "$items" > "$temp_items_file"
            jq -s '.[0] + .[1]' "$output_file" "$temp_items_file" > tmp_${SERVICE_ID}_${COMPARTMENT_ID}.json && mv tmp_${SERVICE_ID}_${COMPARTMENT_ID}.json "$output_file"
            rm -f "$temp_items_file"
        fi
    done
done

# Read the file's content and return it as a JSON-encoded string
content=$(jq -c . < "$output_file")
rm -f "$output_file"
echo "{\"content\": \"$(echo "$content" | sed 's/"/\\"/g')\"}"
