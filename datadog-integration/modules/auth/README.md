# OCI Authentication Module

This Terraform module manages the authentication and authorization setup for Datadog integration in Oracle Cloud Infrastructure (OCI). It creates and configures users, groups, dynamic groups, and policies necessary for Datadog to collect metrics and logs from OCI.

## Features

- Creates or uses existing OCI Identity Domain user
- Creates or uses existing OCI Identity Domain group
- Sets up required IAM policies for Datadog integration
- Creates dynamic resource groups for service connectors and functions
- Configures necessary permissions for metrics and logs collection
- Manages all required IAM components in a single module

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| oci | >= 7.1.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| user_name | The name of the user to create. Only used if existing_user_id is not provided | `string` | `null` | no |
| tags | A map of tags to assign to the resource | `map(string)` | `{}` | no |
| tenancy_id | OCI tenant OCID | `string` | n/a | yes |
| compartment_id | The OCID of the compartment for the dynamic group of all service connector resources | `string` | n/a | yes |
| current_user_id | The OCID of the current user | `string` | n/a | yes |
| idcs_endpoint | The IDCS endpoint URL for the domain | `string` | n/a | yes |
| existing_user_id | The OCID of an existing user to use. If provided, user_name will be ignored | `string` | `null` | no |
| existing_group_id | The OCID of an existing group to use. If provided, a new group will not be created | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| user_id | The OCID of the created or existing user |
| group_id | The OCID of the created or existing group |
| service_connector_dynamic_group_id | The OCID of the service connector dynamic group |
| forwarding_function_dynamic_group_id | The OCID of the forwarding function dynamic group |

## Usage

```hcl
module "auth" {
  source = "./modules/auth"

  user_name        = "datadog-integration"
  tenancy_id       = "ocid1.tenancy.oc1..example"
  compartment_id   = "ocid1.compartment.oc1..example"
  current_user_id  = "ocid1.user.oc1..example"
  idcs_endpoint    = "https://idcs-xxxxx.identity.oraclecloud.com"
  tags = {
    Environment = "Production"
    Project     = "Datadog Integration"
  }
}
```

## IAM Components

The module creates and manages the following IAM components:

1. **User and Group**
   - Creates a new user or uses an existing one
   - Creates a new group or uses an existing one
   - Associates the user with the group

2. **Policies**
   - Creates policies for reading resources in the tenancy
   - Configures permissions for service connectors
   - Sets up function-related permissions
   - Enables usage report access

3. **Dynamic Resource Groups**
   - Creates a dynamic group for service connectors
   - Creates a dynamic group for forwarding functions
   - Configures matching rules based on resource types and compartment

## Notes

- The module supports both creation of new resources and use of existing ones
- All created resources are tagged with provided tags
- Policies include necessary permissions for Datadog integration
- Dynamic groups are configured to match specific resource types in the specified compartment
- The module ensures proper IAM setup for metrics and logs collection 
- The "current user" (person running Terraform / ORM Stack) is needed to extract a valid email address. Creating a new user will send a "reset password" email to that address, which can be ignored, but a valid email must be provided.
