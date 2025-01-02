resource "null_resource" "Login2OCIR" {
   provisioner "local-exec" {
       command = <<EOT
           #!/bin/bash
           set -e

           for i in {1..5}; do
               echo "${var.oci_docker_password}" | docker login ${local.oci_docker_repository} --username ${local.ocir_namespace}/${var.oci_docker_username} --password-stdin && break
               echo "Retrying Docker login... attempt $i"
               sleep 10
           done

           # Check if login was successful
           if [ $i -eq 5 ]; then
               echo "Error: Docker login failed after 5 attempts. Trying to login through Oracle Identity Cloud Service"
               for j in {1..5}; do
                   echo "${var.oci_docker_password}" | docker login ${local.oci_docker_repository} --username ${local.ocir_namespace}/oracleidentitycloudservice/$username --password-stdin && break
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
