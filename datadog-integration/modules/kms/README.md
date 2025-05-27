# OCI KMS Module

This Terraform module manages the Key Management Service (KMS) infrastructure required for securely storing the Datadog API key in Oracle Cloud Infrastructure (OCI). It creates a vault, encryption key, and secret to store the API key securely.

## Features

- Creates a KMS vault for secure key storage
- Generates an AES encryption key
- Securely stores the Datadog API key as a secret
- Manages all KMS-related resources in a single module
- Applies consistent tagging across resources

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| oci | >= 7.1.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| compartment_id | The OCID of the compartment where the vault will be created | `string` | n/a | yes |
| tags | A map of tags to assign to resources | `map(string)` | `{}` | no |
| datadog_api_key | The API key for sending message to datadog endpoints | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| api_key_secret_id | The secret OCID for the API key |

## Usage

```hcl
module "kms" {
  source = "./modules/kms"

  compartment_id   = "ocid1.compartment.oc1..example"
  datadog_api_key  = "your-datadog-api-key"
  tags = {
    Environment = "Production"
    Project     = "Datadog Integration"
  }
}
```

## Infrastructure Components

The module creates and manages the following components:

1. **KMS Vault**
   - Creates a DEFAULT type vault
   - Provides secure storage for keys and secrets
   - Configures vault in the specified compartment

2. **Encryption Key**
   - Generates an AES key with 32-byte length
   - Used for encrypting the Datadog API key
   - Managed through the KMS vault

3. **Secret**
   - Stores the Datadog API key securely
   - Encrypted using the generated AES key
   - Base64 encoded for secure storage

## Notes

- The Datadog API key is marked as sensitive in Terraform
- All resources are tagged with provided tags
- The vault is created as DEFAULT type for standard use cases
- The secret is automatically encrypted using the generated AES key
- The module provides the secret ID for use in other modules 