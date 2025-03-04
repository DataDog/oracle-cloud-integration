locals {
  # Tags for the provisioned resource
  freeform_tags = {
    datadog-terraform = "true"
  }
  home_region_name = [for region in data.oci_identity_regions.all_regions.regions : region.name if region.key == data.oci_identity_tenancy.tenancy_metadata.home_region_key][0]
}

locals {
  logging_compartment_ids = toset(split(",", var.logging_compartments))

  # Parse the content from the external data source
  logging_services = jsondecode(data.external.logging_services.result["content"])

  # Filter services to exclude those in exclude_services
  filtered_services = [
    for service in local.logging_services : service
    if contains(var.include_services, service.id)
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

locals {
  # Combine and group resources by compartment ID (may still contain nested lists)
  compartment_resources = {
    for compartment_group, resources in module.resourcediscovery :
    split("_", compartment_group)[0] => resources.response...
    if length(resources.response) > 0
  }
}

locals {
  /*
    This code snippet processes a list of filtered services to create a mapping of service IDs and resource types to their corresponding categories.

    Steps:
    1. Flatten the `filtered_services` list to create `service_resource_type_list`, which contains objects with combined service ID and resource type as the key, and a list of category names as the value.
    2. Create `service_category_map` using `zipmap`, where the keys are the combined service ID and resource type, and the values are the lists of category names.
    3. Transform `service_category_map` into `transformed_service_map`, where if any category name starts with "all", only those categories are kept; otherwise, all categories are kept.

    Input:
    local.filtered_services = [
      {
        id = "service1",
        resourceTypes = [
          {
            name = "type1",
            categories = ["cat1", "all-cat2"]
          },
          {
            name = "type2",
            categories = ["cat3"]
          }
        ]
      },
      {
        id = "service2",
        resourceTypes = [
          {
            name = "type3",
            categories = ["all-cat4", "cat5"]
          }
        ]
      }
    ]

    Output:
    local.service_map = {
      "service1_type1" = ["all-cat2"],
      "service1_type2" = ["cat3"],
      "service2_type3" = ["all-cat4"]
    }
  */
  # Flatten filtered_services to get service_id_resource_type and corresponding categories
  service_resource_type_list = flatten([
    for service in local.filtered_services : [
      for rt in service.resourceTypes : {
        key       = "${service.id}_${rt.name}" # Combine service ID and resource type as the key
        categories = [for cat in rt.categories : cat.name] # List of category names
      }
    ]
  ])

  # Create service_category_map using zipmap
  service_category_map = zipmap(
    [for item in local.service_resource_type_list : item.key],        # Keys: service_id_resource_type
    [for item in local.service_resource_type_list : item.categories] # Values: category name lists
  )

  service_map = tomap({
    for key, values in local.service_category_map : 
    key => (
      length([for value in values : value if substr(value, 0, 3) == "all"]) > 0 ? 
      [for value in values : value if substr(value, 0, 3) == "all"] : 
      values
    )
  })
}

locals {
  preexisting_service_log_groups = flatten([
    for compartment_id, value in module.logging : 
      value.details.preexisting_log_groups
  ])
  
  # Extract service log groups if they are not null
  datadog_service_log_groups = [
    for compartment_id, value in module.logging : 
      {
        log_group_id = try(value.details.datadog_service_log_group_id, null)
        compartment_id     = compartment_id
      }
      if try(value.details.datadog_service_log_group_id, null) != null
  ]

  service_log_groups = toset(concat(local.preexisting_service_log_groups, local.datadog_service_log_groups))

}
