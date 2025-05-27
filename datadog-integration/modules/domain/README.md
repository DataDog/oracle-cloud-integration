# Domain Module

This module provides common domain operations for Oracle Cloud Infrastructure (OCI) domains. The purpose
is to extract the IDCS endpoint for the input Domain name. This module does not create resources.

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| domain_name | The display name of the domain | string | yes |
| tenancy_id | The OCID of the tenancy | string | yes |

## Outputs

| Name | Description |
|------|-------------|
| idcs_endpoint | The IDCS endpoint for the domain |
| is_default_domain | Whether this is the default domain for the tenancy |

## Usage

```hcl
module "domain" {
  source = "./modules/domain"

  domain_name = "example-domain"
  tenancy_id  = "ocid1.tenancy.oc1..exampleuniqueID"
}

# Access outputs
output "domain_idcs_endpoint" {
  value = module.domain.idcs_endpoint
}

output "is_default_domain" {
  value = module.domain.is_default_domain
}
``` 