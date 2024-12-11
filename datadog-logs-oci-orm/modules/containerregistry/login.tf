resource "null_resource" "recreate_auth_token" {
    provisioner "local-exec" {
        command = <<EOT
            #!/bin/bash
            set -e
            if [ "${var.auth_token}" != "" ]; then
                echo "Using existing auth token..."
                echo ${var.auth_token} > /tmp/new_auth_token.txt
            else
                # Step 1: List existing auth tokens
                echo "Listing existing auth tokens..."
                existing_token_ocid=$(oci iam auth-token list --user-id ${var.user_ocid} \
                    --query "data[?description=='${var.auth_token_description}'].id | [0]" --raw-output)

                if [ "$existing_token_ocid" != "" ]; then
                    echo "Deleting existing auth token: $existing_token_ocid"
                    oci iam auth-token delete --user-id ${var.user_ocid} --auth-token-id $existing_token_ocid --force
                else
                    # Check the total number of existing tokens
                    total_tokens=$(oci iam auth-token list --user-id ${var.user_ocid} --query "length(data)" --raw-output)
                    
                    if [ "$total_tokens" -eq 2 ]; then
                        echo "Error: Total existing tokens are equal to 2. Cannot create a new token."
                        exit 1
                    fi
                    echo "No existing auth token with description '${var.auth_token_description}' found. Proceeding to create a new one."
                fi

                # Step 2: Create a new auth token
                echo "Creating a new auth token..."
                new_token_value=$(oci iam auth-token create --user-id ${var.user_ocid} \
                    --description "${var.auth_token_description}" --query "data.token" --raw-output)

                # Step 3: Sleep for 30 seconds to ensure token propagation
                echo "Waiting for 30 seconds to ensure token availability..."
                sleep 30

                echo $new_token_value > /tmp/new_auth_token.txt
            fi
        EOT
    }
    triggers = {
        always_run = "${timestamp()}"
    }
}

resource "null_resource" "Login2OCIR" {
    depends_on = [null_resource.recreate_auth_token]
    provisioner "local-exec" {
        command = <<EOT
            #!/bin/bash
            set -e

            # Run the current command
            auth_token=$(cat /tmp/new_auth_token.txt && rm -f /tmp/new_auth_token.txt)
            for i in {1..5}; do
                echo "$auth_token" | docker login ${local.oci_docker_repository} --username ${local.ocir_namespace}/${local.username} --password-stdin && break
                echo "Retrying Docker login... attempt $i"
                sleep 5
            done

            # Check if login was successful
            if [ $i -eq 5 ]; then
                echo "Error: Docker login failed after 5 attempts."
                exit 1
            fi
        EOT
    }
    triggers = {
        always_run = "${timestamp()}"
    }
}
