locals {
    allowed_service_ids = [for key, value in var.service_map : split("_", key)[0]]
    filtered_logs = flatten([
        for log_group in data.oci_logging_logs.existing_logs : [
            for log in log_group.logs :
            # Filter logs based on the allowed_services variable
            {
                log_group_ocid = log.log_group_id
                #log_ocid       = log.id
                state          = log.state
                #log_type       = log.log_type
                compartment_id = log.compartment_id
                is_enabled     = log.is_enabled
                resource_id    = try(log.configuration[0].source[0].resource, null)
                service_id     = try(log.configuration[0].source[0].service, null)
                category       = try(log.configuration[0].source[0].category, null)
            } if contains(local.allowed_service_ids, try(log.configuration[0].source[0].service, ""))
        ]
    ])

    # Map for resourceId_service_category => [{loggroupid, state, is_enabled}]
    logs_map = tomap({
        for log in local.filtered_logs : 
        "${log.resource_id}_${log.service_id}_${log.category}" => {
            loggroupid = log.log_group_ocid
            state      = log.state
            is_enabled = log.is_enabled
        }
    })
}

locals {
    resource_evaluation = flatten([
        for resource in var.resources : [
            for category in lookup(var.service_map, "${resource.groupId}_${resource.resourceType}", []) : {
                service_id    = resource.groupId
                resource_id   = resource.identifier
                resource_name = resource.displayName
                category      = category
                loggroup      = lookup(local.logs_map, "${resource.identifier}_${resource.groupId}_${category}", null)
            }
        ]
    ])

    resources_without_logs = [
        for item in local.resource_evaluation : {
            service_id    = item.service_id
            resource_id   = item.resource_id
            resource_name = item.resource_name
            category      = item.category
        }
        if item.loggroup == null
    ]

    loggroup_ids = toset([
        for item in local.resource_evaluation : item.loggroup.loggroupid
        if item.loggroup != null
    ])
}
