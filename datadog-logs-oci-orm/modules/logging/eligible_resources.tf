# Step 1: Fetch logging services
resource "null_resource" "fetch_logging_services" {
  provisioner "local-exec" {
    command = <<EOT
      # Export compartment OCID from Terraform variable
      export COMPARTMENT_ID="${var.compartment_ocid}"
      oci logging service list --all --query "data[].{id:id, resourceTypes:\"resource-types\"[].{name:name, categories:categories[].{name:name}}}" > oci_response_$${COMPARTMENT_ID}.json || echo "Error fetching logging services" >> error.log
    EOT
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}
/*
# Step 2: Fetch resources
resource "null_resource" "oci_cli_query" {
  depends_on = [null_resource.fetch_logging_services]

  provisioner "local-exec" {
    command = <<EOT
      # Export exclude_services from Terraform variable
      export EXCLUDE_SERVICES="${join(" ", var.exclude_services)}"
      # Export compartment OCID from Terraform variable
      export COMPARTMENT_ID="${var.compartment_ocid}"

      output_file="oci_resources_$${COMPARTMENT_ID}.json"
      echo "[]" > $output_file # Initialize the output file with an empty JSON array
      # Parse oci_response.json
      jq -c '.[]' oci_response_$${COMPARTMENT_ID}.json | while read service; do
        service_id=$(echo $service | jq -r '.id')
        # Check if the service is in the exclude list
        if [[ " $EXCLUDE_SERVICES " =~ " $service_id " ]]; then
          echo "Service $service_id is in the exclude list, skipping..."
          continue
        fi
        resource_types=$(echo $service | jq -r '.resourceTypes[].name')

        # Perform OCI CLI query for each resource type
        for rt in $resource_types; do
          echo "Querying resources for service: $service_id, resource type: $rt"

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
              echo "ServiceError for $service_id, resource type: $rt" >> error.log
              break
            fi
            
            # Extract next page token
            next_page=$(echo "$response" | jq -r '."opc-next-page" // "null"')

            # Extract and transform items
            items=$(echo "$response" | jq --arg service_id "$service_id" -c '[.data.items[] | {compartmentId: ."compartment-id", displayName: ."display-name", identifier: ."identifier", resourceType: ."resource-type", serviceId: $service_id}]')
            # Append items to the output file if not empty
            if [ "$(echo "$items" | jq length)" -gt 0 ]; then
              temp_items_file="temp_items_$${COMPARTMENT_ID}.json"
              echo "$items" > "$temp_items_file"
              jq -s '.[0] + .[1]' "$output_file" "$temp_items_file" > tmp_$${COMPARTMENT_ID}.json && mv tmp_$${COMPARTMENT_ID}.json "$output_file"
              rm -f "$temp_items_file"
            fi
          done
        done
      done
    EOT
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}
*/
