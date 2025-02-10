locals {
    resource_types_string = join(",", [for rt in var.resource_types : rt])
}
