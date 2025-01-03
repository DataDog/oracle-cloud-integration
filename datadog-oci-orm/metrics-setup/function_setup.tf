resource "null_resource" "recreate_auth_token" {
    count = "${var.auth_token != "" ? 0 : 1}"
    provisioner "local-exec" {
        command = <<EOT
            #!/bin/bash
            set -e

            # Step 1: List existing auth tokens
            echo "Listing existing auth tokens..."
            existing_token_ocid=$(oci iam auth-token list --user-id ${local.user_ocid} \
                --query "data[?description=='${var.auth_token_description}'].id | [0]" --raw-output)

            if [ "$existing_token_ocid" != "" ]; then
                echo "Deleting existing auth token: $existing_token_ocid"
                oci iam auth-token delete --user-id ${local.user_ocid} --auth-token-id $existing_token_ocid --force
            else
                # Check the total number of existing tokens
                total_tokens=$(oci iam auth-token list --user-id ${local.user_ocid} --query "length(data)" --raw-output)

                if [ "$total_tokens" -eq 2 ]; then
                    echo "Error: Total existing tokens are equal to 2. Cannot create a new token."
                    exit 1
                fi
                echo "No existing auth token with description '${var.auth_token_description}' found. Proceeding to create a new one."
            fi

            # Step 2: Create a new auth token
            echo "Creating a new auth token..."
            new_token_value=$(oci iam auth-token create --user-id ${local.user_ocid} \
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
               echo "$auth_token" | docker login ${local.registry_domain} --username ${local.ocir_namespace}/${local.username} --password-stdin && break
               echo "Retrying Docker login... attempt $i"
               sleep 10
           done

           # Check if login was successful
           if [ $i -eq 5 ]; then
               echo "Error: Docker login failed after 5 attempts. Trying to login through Oracle Identity Cloud Service"
               for j in {1..5}; do
                   echo "$auth_token" | docker login ${local.registry_domain} --username ${local.ocir_namespace}/oracleidentitycloudservice/$username --password-stdin && break
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

### Repository in the Container Image Registry for the container images underpinning the function
resource "oci_artifacts_container_repository" "function_repo" {
  # note: repository = store for all images versions of a specific container image - so it included the function name
  depends_on     = [null_resource.Login2OCIR]
  compartment_id = var.compartment_ocid
  display_name   = "${local.ocir_repo_name}/${local.function_name}"
  is_public      = false
  defined_tags   = {}
  freeform_tags  = local.freeform_tags
}

# ### build the function into a container image and push that image to the repository in the OCI Container Image Registry
resource "null_resource" "FnImagePushToOCIR" {
  depends_on = [oci_artifacts_container_repository.function_repo, oci_functions_application.metrics_function_app, null_resource.Login2OCIR]

  provisioner "local-exec" {
    command = "echo '${var.auth_token}' |  docker login ${local.oci_docker_repository} --username ${local.ocir_namespace}/${local.username} --password-stdin"
  }

  # remove function image (if it exists) from local container registry
  provisioner "local-exec" {
    command     = "image=$(docker images | grep ${local.function_name} | awk -F ' ' '{print $3}') ; docker rmi -f $image &> /dev/null ; echo $image"
    working_dir = "metrics-function"
  }

  # build and tag the image from the docker file
  provisioner "local-exec" {
    command     = "docker build -t ${local.docker_image_path} . --no-cache"
    working_dir = "metrics-function"
  }

  # Push the docker image to the OCI registry
  provisioner "local-exec" {
    command     = "docker push ${local.docker_image_path}"
    working_dir = "metrics-function"
  }

  # remove function image (if it exists) from local container registry
  provisioner "local-exec" {
    command     = "docker rmi -f `docker images | grep ${local.function_name} | awk -F ' ' '{print $3}'`> /dev/null"
    working_dir = "metrics-function"
  }

}

resource "null_resource" "wait_for_image" {
  depends_on = [null_resource.FnImagePushToOCIR]
  provisioner "local-exec" {
    command = "sleep 60"
  }
}
