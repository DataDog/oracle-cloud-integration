# OCI API Key Module

This Terraform module manages the creation and lifecycle of Oracle Cloud Infrastructure (OCI) API keys for users. It handles key generation, upload to OCI, and automatic cleanup of old keys when quota limits are reached.

## Features

- Generates RSA keys in PKCS8 format, to be used as OCI API keys
- Automatically uploads keys to OCI Identity Domains
- Handles key quota limits by removing oldest keys when necessary
- Ensures key visibility through polling mechanism
- Manages key lifecycle through Terraform

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| oci | >= 7.1.0 |
| local | latest |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| compartment_ocid | The OCID of the compartment | `string` | n/a | yes |
| region | The region to deploy to | `string` | n/a | yes |
| tenancy_ocid | The OCID of the tenancy | `string` | n/a | yes |
| existing_user_id | The OCID of the user for whom to create the API key | `string` | n/a | yes |
| idcs_endpoint | The IDCS endpoint URL for the domain | `string` | n/a | yes |
| tags | A map of tags to assign to the resource | `map(string)` | `{}` | no |
| auth_method | Authentication method for OCI CLI commands. Set to '--auth api_key' if running from the command line, leave blank if running from OCI Resource Manager | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| private_key | The generated private key (sensitive) |

## Usage

```hcl
module "key" {
  source = "./modules/key"

  compartment_ocid  = "ocid1.compartment.oc1..example"
  region           = "us-ashburn-1"
  tenancy_ocid     = "ocid1.tenancy.oc1..example"
  existing_user_id = "ocid1.user.oc1..example"
  idcs_endpoint    = "https://idcs-xxxxx.identity.oraclecloud.com"
  tags = {
    Environment = "Production"
    Project     = "Datadog Integration"
  }
}
```

## Key Management

The module performs the following operations:

1. Generates a new RSA key pair in PKCS8 format
2. Uploads the public key to OCI Identity Domains
3. If the user has reached their key quota limit, the oldest key is automatically removed
4. Verifies key visibility through polling (up to 12 attempts with 5-second intervals)
5. Stores the private key as a sensitive output

## Notes

- The module uses local-exec provisioners to interact with the OCI CLI
- The size is set to 2048 bits
- The module includes error handling for quota limits and key visibility verification
- Private keys are marked as sensitive in Terraform outputs 