data "local_file" "dd_iac_version" {
  filename = "${path.module}/../../VERSION"
}
