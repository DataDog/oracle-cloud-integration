data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_ocid
}

data "local_sensitive_file" "private_key" {
  filename = "/tmp/sshkey"
  depends_on = [terraform_data.manage_api_key]
}
