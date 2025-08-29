terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
  }
}

resource "terraform_data" "manage_api_key" {
  triggers_replace = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command     = <<-EOT
      set -e

      # Suppress OCI CLI warnings
      export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True

      # Clean up any existing key files
      rm -f /tmp/sshkey*

      # Generate private key in PKCS8 format
      ssh-keygen -b 2048 -t rsa -m PKCS8 -f /tmp/sshkey -q -N "" -C "oci-api-key"
      openssl rsa -in /tmp/sshkey -pubout -out /tmp/sshkey.pem
      echo "SSH key pair generated successfully"

      # Get user's IDCS ID
      echo "Starting user lookup for OCID: ${local.user_id}"
      
      # Execute OCI CLI command with debugging
      if ! OCI_OUTPUT=$(oci identity-domains users list ${local.endpoint_param} ${var.auth_method} --read-timeout 60 --all --raw-output 2>&1); then
        echo "ERROR: OCI CLI command failed"
        echo "Command output: $OCI_OUTPUT"
        exit 1
      fi
      
      echo "OCI CLI command completed successfully"
      echo "Parsing JSON response with jq..."
      
      # Parse JSON with jq
      if ! USER_INFO=$(echo "$OCI_OUTPUT" | jq -r '.data.resources[] | select(.ocid == "'"${local.user_id}"'") | .id' 2>&1); then
        echo "ERROR: jq parsing failed"
        echo "Raw OCI output (first 1000 chars):"
        echo "$OCI_OUTPUT" | head -c 1000
        exit 1
      fi
      
      echo "JSON parsing completed. User ID: $USER_INFO"
      
      if [ -z "$USER_INFO" ] || [ "$USER_INFO" = "null" ]; then
        echo "ERROR: Failed to find user with OCID: ${local.user_id}"
        echo "Raw OCI output (first 1000 chars):"
        echo "$OCI_OUTPUT" | head -c 1000
        exit 1
      fi
      
      echo "User lookup successful. Proceeding to key creation..."

      # Prepare key creation
      echo "Reading public key content..."
      KEY_CONTENT=$(cat /tmp/sshkey.pem)
      echo "Public key content read successfully"
      
      echo '["urn:ietf:params:scim:schemas:oracle:idcs:apikey"]' > /tmp/schemas.json
      echo "{\"value\": \"$USER_INFO\"}" > /tmp/user.json

      # Function to create API key
      create_key() {
        oci identity-domains api-key create \
          --key "$KEY_CONTENT" \
          --fingerprint "" \
          --schemas file:///tmp/schemas.json \
          --user file:///tmp/user.json \
          ${local.endpoint_param} \
          ${var.auth_method}
      }

      # Try to create key, handle quota limit if needed
      if ! UPLOAD_OUTPUT=$(create_key 2>&1); then
        if echo "$UPLOAD_OUTPUT" | grep -q "maximum quota limit"; then
          echo "API key limit reached, removing oldest key..."
          
          # Get and delete oldest key
          OLDEST_KEY=$(oci identity-domains api-keys list ${local.endpoint_param} ${var.auth_method} \
            --filter "user.value eq \"$USER_INFO\"" --all --raw-output | \
            jq -r '.data.resources[0].id')
          
          if [ -n "$OLDEST_KEY" ] && [ "$OLDEST_KEY" != "null" ]; then
            oci identity-domains api-key delete --api-key-id "$OLDEST_KEY" --force ${local.endpoint_param} ${var.auth_method}
            UPLOAD_OUTPUT=$(create_key 2>&1) || { echo "Failed to create new key after deletion"; exit 1; }
          else
            echo "No existing keys found to delete"
            exit 1
          fi
        else
          echo "Failed to create key: $UPLOAD_OUTPUT"
          exit 1
        fi
      fi

      # Extract and save fingerprint
      NEW_FINGERPRINT=$(echo "$UPLOAD_OUTPUT" | jq -r '.data.fingerprint')
      if [ -z "$NEW_FINGERPRINT" ] || [ "$NEW_FINGERPRINT" = "null" ]; then
        echo "Failed to get fingerprint from response: $UPLOAD_OUTPUT"
        exit 1
      fi
      # Wait for key to appear
      echo "Waiting for key to appear in OCI..."
      for i in {1..12}; do
        if oci identity-domains api-keys list ${local.endpoint_param} ${var.auth_method} \
          --filter "user.value eq \"$USER_INFO\"" --all --raw-output | \
          jq -e '.data.resources[] | select(.fingerprint == "'"$NEW_FINGERPRINT"'")' > /dev/null; then
          echo "Key is now visible in OCI"
          exit 0
        fi
        echo "Waiting... ($i/12)"
        sleep 5
      done
      echo "ERROR: Key did not appear in OCI after polling"
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
