data "oci_identity_users" "docker_registry_user" {
  compartment_id = var.tenancy_ocid
  name           = "DatadogAuthWriteUser"
}

data "oci_identity_auth_tokens" "docker_registry_user_tokens" {
  count   = local.is_service_user_available ? 1 : 0
  user_id = local.datadog_write_user_id
}

# Local variables to manage login and token value for the service account user.
locals {
  token_ids                 = [for token in data.oci_identity_auth_tokens.docker_registry_user_tokens : token.id]
  is_service_user_available = length(data.oci_identity_users.docker_registry_user.users) == 1 ? true : false
  datadog_write_user_login  = local.is_service_user_available ? data.oci_identity_users.docker_registry_user.users[0].name : ""
  datadog_write_user_id     = local.is_service_user_available ? data.oci_identity_users.docker_registry_user.users[0].id : ""
  token_value               = local.is_service_user_available ? jsondecode(data.external.auth_token_fetch[0].result.output)["token"] : ""
}

# external script to manage the auth tokens. Destroy existing ones and generate new
data "external" "auth_token_fetch" {
  count   = local.is_service_user_available ? 1 : 0
  program = ["python", "${path.module}/auth_token.py"]
  query = {
    "user_ocid" : local.datadog_write_user_id
    "region" : local.home_region_name
    "token_ids" : join(",", [for token in data.oci_identity_auth_tokens.docker_registry_user_tokens[0].tokens : token.id])
  }
}

resource "null_resource" "Login2OCIR" {
  count      = local.is_service_user_available ? 1 : 0
  depends_on = [data.external.auth_token_fetch]
  provisioner "local-exec" {
    command = <<EOT
           #!/bin/bash
           set -e
           echo "Wait before trying to attempt docker login..."
           sleep 60
           for i in {1..5}; do
               echo "${local.token_value}" | docker login ${local.oci_docker_repository} --username ${local.ocir_namespace}/${local.datadog_write_user_login} --password-stdin && break
               echo "Retrying Docker login... attempt $i"
               sleep 60
           done

           # Check if login was successful
           if [ $i -eq 5 ]; then
               echo "Error: Docker login failed after 5 attempts. Trying to login through Oracle Identity Cloud Service"
               for j in {1..5}; do
                   echo "${local.token_value}" | docker login ${local.oci_docker_repository} --username ${local.ocir_namespace}/oracleidentitycloudservice/${local.datadog_write_user_login} --password-stdin && break
                   echo "Retrying Docker login through Identity service... attempt $j"
                   sleep 60
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
  count = local.is_service_user_available ? 1 : 0
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
  count      = local.is_service_user_available ? 1 : 0
  depends_on = [oci_artifacts_container_repository.function_repo, null_resource.Login2OCIR, oci_functions_application.metrics_function_app]

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
  count      = local.is_service_user_available ? 1 : 0
  depends_on = [null_resource.FnImagePushToOCIR]
  provisioner "local-exec" {
    command = "sleep 60"
  }
}
