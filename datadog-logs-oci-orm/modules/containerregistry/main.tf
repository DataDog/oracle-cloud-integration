### Repository in the Container Image Registry for the container images underpinning the function 
resource "oci_artifacts_container_repository" "function_repo" {
  # note: repository = store for all images versions of a specific container image - so it included the function name
  depends_on     = [null_resource.Login2OCIR]
  compartment_id = var.compartment_ocid
  display_name   = "${local.repo_name}"
  is_public      = false
  defined_tags   = {}
  freeform_tags  = var.freeform_tags
}

# ### build the function into a container image and push that image to the repository in the OCI Container Image Registry
resource "null_resource" "FnImagePushToOCIR" {
  depends_on = [oci_artifacts_container_repository.function_repo, null_resource.Login2OCIR]
  #Delete the local image, if it exists
  provisioner "local-exec" {
    command     = "image=$(docker images | grep ${local.docker_image_path} | awk -F ' ' '{print $3}') ; docker rmi -f $image &> /dev/null ; echo $image"
    working_dir = "logs-function"
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e

      TIMESTAMP=$(date +%s)
      docker build -t ${local.docker_image_path}:latest --no-cache -t ${local.docker_image_path}:$TIMESTAMP . || { echo \"Build failed!\"; exit 1; }
      
      docker push ${local.docker_image_path}:latest || { echo \"Docker push latest tagged image failed!\"; exit 1; }
      docker push ${local.docker_image_path}:$TIMESTAMP || { echo \"Docker push timestamp tagged image failed!\"; exit 1; }
    EOT
    working_dir = "logs-function"
  }

  # remove function image (if it exists) from local container registry
  provisioner "local-exec" {
    command     = "docker rmi -f `docker images | grep ${local.docker_image_path} | awk -F ' ' '{print $3}'` &> /dev/null"
    working_dir = "logs-function"
  }
}
