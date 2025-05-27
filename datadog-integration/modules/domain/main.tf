data "oci_identity_domains" "domains" {
  compartment_id = var.tenancy_id
}

data "oci_identity_domain" "domain" {
  domain_id = [for domain in data.oci_identity_domains.domains.domains : domain.id if domain.display_name == var.domain_name][0]
}
