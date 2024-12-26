locals {
    resource_type_names = join(",", [for rt in var.resource_types : rt.name])
}
