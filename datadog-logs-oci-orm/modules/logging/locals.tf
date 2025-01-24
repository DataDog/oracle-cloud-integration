locals {
    resource_evaluation = flatten([
        for resource in var.resources : [
            for category in lookup(var.service_map, "${resource.groupId}_${resource.resourceType}", []) : {
                service_id    = resource.groupId
                resource_id   = resource.identifier
                resource_name = resource.displayName
                category      = category
                time_created   = lookup(resource, "timeCreated", "")
                loggroup      = lookup(var.logs_map, "${resource.identifier}_${resource.groupId}_${category}", null)
            }
        ]
    ])
    
    sorted_keys = sort([for item in local.resource_evaluation : "${item.time_created}_${item.resource_id}_${item.service_id}_${item.category}"])
    sorted_resource_evaluation = [
        for key in local.sorted_keys : lookup(
            { for item in local.resource_evaluation : "${item.time_created}_${item.resource_id}_${item.service_id}_${item.category}" => item },
            key
        )
    ]
}

locals {
    datadog_log_group_id = try(data.oci_logging_log_groups.datadog_log_group.log_groups[0].id, null)
    loggroups = toset([
        for item in local.sorted_resource_evaluation : {
            loggroupid    = item.loggroup.loggroupid
            compartmentid = item.loggroup.compartmentid
        }
        if item.loggroup != null && try(item.loggroup.loggroupid, "") != local.datadog_log_group_id
    ])

    resources_without_logs = zipmap(
        [for idx, item in range(length(local.sorted_resource_evaluation)) :
            "${local.sorted_resource_evaluation[idx].resource_name}_${local.sorted_resource_evaluation[idx].category}_${idx}"
            if local.sorted_resource_evaluation[idx].loggroup == null || try(local.sorted_resource_evaluation[idx].loggroup.loggroupid, "") == local.datadog_log_group_id
        ],
        [for item in local.sorted_resource_evaluation : item if item.loggroup == null || try(item.loggroup.loggroupid, "") == local.datadog_log_group_id]
    )
}
