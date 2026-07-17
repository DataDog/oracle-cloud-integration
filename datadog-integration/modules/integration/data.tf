data "external" "stack_info" {
  program = ["python", "${path.module}/stack_id_from_job.py"]
  query   = {}
}

# Single source of truth for the release version. The VERSION file at the repo
# root is written by developers when preparing a release, and the release
# workflow reads the same file when creating the GitHub tag.
data "local_file" "dd_iac_version" {
  filename = "${path.root}/VERSION"
}
