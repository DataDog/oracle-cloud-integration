output "containerregistry_details" {
  description = "Output of pushing image to container registry"
  value       = {
    repository_ocid = oci_artifacts_container_repository.function_repo.id
    repository_name = oci_artifacts_container_repository.function_repo.display_name
  }
}
