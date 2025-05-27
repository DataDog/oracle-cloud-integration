# OCI Regional Stacks Module

This Terraform module sets up the regional infrastructure components required for Datadog integration in Oracle Cloud Infrastructure (OCI). It creates and manages Functions applications, networking components, and the necessary configuration for forwarding logs and metrics to Datadog.

## Features

- Creates OCI Functions application for Datadog integration
- Sets up log and metrics forwarding functions
- Manages networking infrastructure (VCN, subnets, gateways)
- Supports both new and existing subnet configurations
- Configures necessary security and access settings
- Handles regional-specific configurations

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| oci | >= 7.1.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| tenancy_ocid | OCI tenant OCID | `string` | n/a | yes |
| region | OCI Region | `string` | n/a | yes |
| compartment_ocid | The OCID of the compartment where resources will be created | `string` | n/a | yes |
| datadog_site | The Datadog site to send data to (e.g., datadoghq.com, datadoghq.eu) | `string` | n/a | yes |
| tags | A map of tags to assign to the resource | `map(string)` | `{ ownedby = "datadog" }` | no |
| home_region | The name of the home region | `string` | n/a | yes |
| api_key_secret_id | The secret ID for the Datadog API key | `string` | n/a | yes |
| region_key | The 3 letter key of the region used | `string` | n/a | yes |
| subnet_partial_name | Optional partial name of an existing subnet to use | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| output_ids | Map containing the IDs of created resources: subnet and function_app |

## Usage

```hcl
module "regional_stacks" {
  source = "./modules/regional-stacks"

  tenancy_ocid       = "ocid1.tenancy.oc1..example"
  region            = "us-ashburn-1"
  compartment_ocid  = "ocid1.compartment.oc1..example"
  datadog_site      = "datadoghq.com"
  home_region       = "us-ashburn-1"
  api_key_secret_id = "ocid1.vaultsecret.oc1..example"
  region_key        = "iad"
  tags = {
    Environment = "Production"
    Project     = "Datadog Integration"
  }
}
```

## Infrastructure Components

The module creates and manages the following components:

1. **Functions Application**
   - Creates a Functions application for Datadog integration
   - Sets up two functions:
     - Logs forwarder (1024 MB memory)
     - Metrics forwarder (512 MB memory)
   - Configures necessary environment variables and settings

2. **Networking**
   - Optionally creates a new VCN with:
     - Private subnet
     - NAT Gateway
     - Service Gateway
   - Or uses an existing subnet if `subnet_partial_name` is provided
   - Validates subnet existence when using existing subnet

3. **Configuration**
   - Sets up necessary environment variables for Datadog integration
   - Configures function memory and resources
   - Manages security settings and access controls

## Notes

- The module supports both new and existing subnet configurations
- Functions are configured with appropriate memory allocations for their tasks
- All resources are tagged with provided tags
- The module includes validation for existing subnet configuration
- Networking components are created only when not using an existing subnet. Existing subnets are discovered by using a regexp search on the subnet name, via the `subnet_partial_name` input variable. 