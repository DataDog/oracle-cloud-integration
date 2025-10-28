terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=7.1.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Generate RSA private key for API authentication
# This key is rotated on every apply to comply with security policies
resource "tls_private_key" "datadog_api_key" {
  algorithm = "RSA"
  rsa_bits  = 2048

  # Force key rotation on every apply for security compliance
  lifecycle {
    replace_triggered_by = [terraform_data.key_rotation_trigger]
  }
}

# Trigger to force key rotation on every apply
resource "terraform_data" "key_rotation_trigger" {
  input = timestamp()
}

# Data source to get user's IDCS ID from their OCID
# Note: Identity Domains data sources retrieve all users, we filter in Terraform
data "oci_identity_domains_users" "user_lookup" {
  idcs_endpoint = var.idcs_endpoint
}

# Local to find the specific user by OCID
locals {
  user_idcs_id = [
    for user in data.oci_identity_domains_users.user_lookup.users :
    user.id if try(user.ocid, "") == var.existing_user_id
  ][0]
}

# Create API key for the user using native Terraform resource
resource "oci_identity_domains_api_key" "datadog_key" {
  idcs_endpoint = var.idcs_endpoint
  
  # The key value in PEM format
  key = tls_private_key.datadog_api_key.public_key_pem
  
  # Required schemas for Identity Domains API key
  schemas = ["urn:ietf:params:scim:schemas:oracle:idcs:apikey"]
  
  # Link to the user
  user {
    value = local.user_idcs_id
  }

  # Lifecycle policy for key rotation
  # create_before_destroy ensures smooth rotation:
  # 1. New key is created first
  # 2. Downstream resources (integration) updated with new key
  # 3. Old key is deleted
  lifecycle {
    create_before_destroy = true
  }
}

# Optional: Add a time_sleep to allow for eventual consistency
resource "time_sleep" "wait_for_key_propagation" {
  depends_on      = [oci_identity_domains_api_key.datadog_key]
  create_duration = "30s"
}
