#!/bin/bash

output_file="oci_logging_services.json"
echo "[]" > $output_file # Initialize the output file with an empty JSON array

# Fetch logging services using OCI CLI
response=$(oci logging service list --all --query "data[].{id:id, resourceTypes:\"resource-types\"[].{name:name, categories:categories[].{name:name}}}" --output json)

# Write the response to the output file
echo "$response" > "$output_file"

# Output the response in a valid JSON map for Terraform's external data source
content=$(jq -c . < "$output_file") # Ensure the file's content is compact JSON
echo "{\"content\": \"$(echo "$content" | sed 's/"/\\"/g')\"}" # Escape quotes for JSON compatibility
