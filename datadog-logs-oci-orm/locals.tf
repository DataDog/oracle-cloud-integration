locals {
  # Tags for the provisioned resource
  freeform_tags = {
    datadog-terraform = "true"
  }
}

locals {
  # Decode the uploaded CSV file into a map
  logging_csv_content     = base64decode(var.logging_compartments_csv)
  logging_compartments = csvdecode(local.logging_csv_content)

  # Extract only the compartment IDs into a list
  logging_compartment_ids = [for row in local.logging_compartments : row.compartment_id]

  # Parse the content from the external data source
  logging_services = jsondecode(data.external.logging_services.result["content"])

  # Filter services to exclude those in exclude_services
  filtered_services = [
    for service in local.logging_services : service
    if !contains(var.exclude_services, service.id)
  ]

  # Generate a Cartesian product of compartments and filtered services
  logging_targets = flatten([
    for compartment_id in local.logging_compartment_ids : [
      for service in local.filtered_services : {
        compartment_id = compartment_id
        service_id     = service.id
        resource_types = service.resourceTypes
      }
    ]
  ])
}
