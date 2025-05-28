data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_domains" "domains" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_domain" "selected_domain" {
  domain_id = [for domain in data.oci_identity_domains.domains.domains : domain.id if domain.display_name == var.domain_name][0]
}

data "local_sensitive_file" "private_key" {
  filename = "/tmp/sshkey"
  depends_on = [terraform_data.manage_api_key]
}
