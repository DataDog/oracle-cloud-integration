resource "null_resource" "recreate_auth_token" {
    count = "${var.auth_token != "" ? 0 : 1}"
    provisioner "local-exec" {
        command = <<EOT
            #!/bin/bash
            set -e

            # Step 1: List existing auth tokens
            echo "Listing existing auth tokens..."
            existing_token_ocid=$(oci iam auth-token list --user-id ${var.current_user_ocid} \
                --query "data[?description=='${var.auth_token_description}'].id | [0]" --raw-output)

            if [ "$existing_token_ocid" != "" ]; then
                echo "Deleting existing auth token: $existing_token_ocid"
                oci iam auth-token delete --user-id ${var.current_user_ocid} --auth-token-id $existing_token_ocid --force
            else
                # Check the total number of existing tokens
                total_tokens=$(oci iam auth-token list --user-id ${var.current_user_ocid} --query "length(data)" --raw-output)
                
                if [ "$total_tokens" -eq 2 ]; then
                    echo "Error: Total existing tokens are equal to 2. Cannot create a new token."
                    exit 1
                fi
                echo "No existing auth token with description '${var.auth_token_description}' found. Proceeding to create a new one."
            fi

            # Step 2: Create a new auth token
            echo "Creating a new auth token..."
            new_token_value=$(oci iam auth-token create --user-id ${var.current_user_ocid} \
                --description "${var.auth_token_description}" --query "data.token" --raw-output)

            # Step 3: Sleep for 30 seconds to ensure token propagation
            echo "Waiting for 60 seconds to ensure token availability..."
            sleep 60

            echo $new_token_value > /tmp/new_auth_token.txt
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
            if [ "${var.auth_token}" != "" ]; then
                auth_token="${var.auth_token}"
            else
                auth_token=$(cat /tmp/new_auth_token.txt && rm -f /tmp/new_auth_token.txt)
            fi
            for i in {1..5}; do
                echo "$auth_token" | docker login ${local.registry_domain} --username ${local.tenancy_namespace}/${local.username} --password-stdin && break
                echo "Retrying Docker login... attempt $i"
                sleep 10
            done

            # Check if login was successful
            if [ $i -eq 5 ]; then
                echo "Error: Docker login failed after 5 attempts. Trying to login through Oracle Identity Cloud Service"
                for j in {1..5}; do
                    echo "$auth_token" | docker login ${local.registry_domain} --username ${local.tenancy_namespace}/oracleidentitycloudservice/$username --password-stdin && break
                    echo "Retrying Docker login through Identity service... attempt $j"
                    sleep 5
                done
                if [ $j -eq 5 ]; then
                    echo "Error: Docker login failed after 5 attempts."
                    exit 1
                fi
            fi
        EOT
    }
    triggers = {
        always_run = "${timestamp()}"
    }
}
