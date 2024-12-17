locals {
  # Tags for the provisioned resource
  freeform_tags = {
    datadog-terraform = "true"
  }
}

locals {
  # Name for tenancy namespace, metadata and regions
  oci_regions = tomap({
    for reg in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions :
    reg.region_name => reg
  })
  oci_region_key      = lower(local.oci_regions[var.region].region_key)
  tenancy_home_region = data.oci_identity_tenancy.tenancy_metadata.home_region_key
}

locals {
  # Decode the uploaded CSV file into a map
  logging_csv_content     = base64decode(var.logging_compartments_csv)
  logging_compartments = csvdecode(local.logging_csv_content)

  # Extract only the compartment IDs into a list
  logging_compartment_ids = [for row in local.logging_compartments : row.compartment_id]
}
