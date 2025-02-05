locals {
    # List of allowed service IDs extracted from the service map keys
    allowed_service_ids = [for key, value in var.service_map : split("_", key)[0]]
    
    # Flattened list of logs filtered based on allowed service IDs
    filtered_logs = flatten([
        for log_group in data.oci_logging_logs.existing_logs : [
            for log in log_group.logs :
            # Filter logs based on the allowed_services variable
            {
                log_group_id   = log.log_group_id
                state          = log.state
                compartment_id = log.compartment_id
                is_enabled     = log.is_enabled
                resource_id    = try(log.configuration[0].source[0].resource, null)
                service_id     = try(log.configuration[0].source[0].service, null)
                category       = try(log.configuration[0].source[0].category, null)
            } if contains(local.allowed_service_ids, try(log.configuration[0].source[0].service, ""))
        ]
    ])
    
    # Map for resource_id_service_category => [{log_group_id, state, is_enabled}]
    logs_map = tomap({
        for log in local.filtered_logs : 
        "${log.resource_id}_${log.service_id}_${log.category}" => {
            log_group_id   = log.log_group_id
            state          = log.state
            is_enabled     = log.is_enabled
            compartment_id = log.compartment_id
        }
    })
}

locals {
    # Flattened list of resource evaluations based on the service map
    resource_evaluation = toset(flatten([
        for resource in var.resources : [
            for category in lookup(var.service_map, "${resource.groupId}_${resource.resourceType}", []) : {
                service_id    = resource.groupId
                resource_id   = resource.identifier
                resource_name = resource.displayName
                category      = category
                time_created  = lookup(resource, "timeCreated", "")
                log_group     = lookup(local.logs_map, "${resource.identifier}_${resource.groupId}_${category}", null)
            }
        ]
    ]))
    
    # Updated resource evaluation with logs outside the compartment
    updated_resource_evaluation = [
        for resource in local.resource_evaluation : {
            service_id    = resource.service_id
            resource_id   = resource.resource_id
            resource_name = resource.resource_name
            category      = resource.category
            time_created  = resource.time_created
            log_group     = (data.external.logs_outside_compartment["${resource.resource_id}-${resource.category}"].result.content != "" ? 
                            jsondecode(data.external.logs_outside_compartment["${resource.resource_id}-${resource.category}"].result.content) : resource.log_group)
        }
    ]
}

locals {
    # Datadog log group ID
    datadog_service_log_group_id = try(data.oci_logging_log_groups.datadog_service_log_group.log_groups[0].id, null)
    
    # Set of log groups excluding the Datadog log group
    log_groups = toset([
        for item in local.updated_resource_evaluation : {
            log_group_id   = item.log_group.log_group_id
            compartment_id = item.log_group.compartment_id
        }
        if item.log_group != null && try(item.log_group.log_group_id, "") != local.datadog_service_log_group_id
    ])

    # Map of resources without logs or with logs in the Datadog log group
    resources_without_logs = zipmap(
        [for idx, item in range(length(local.updated_resource_evaluation)) :
            "${local.updated_resource_evaluation[idx].resource_id}_${local.updated_resource_evaluation[idx].category}"
            if local.updated_resource_evaluation[idx].log_group == null || try(local.updated_resource_evaluation[idx].log_group.log_group_id, "") == local.datadog_service_log_group_id
        ],
        [for item in local.updated_resource_evaluation : item if item.log_group == null || try(item.log_group.log_group_id, "") == local.datadog_service_log_group_id]
    )
    
}
