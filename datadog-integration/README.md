# Purpose

This folder defines the OCI stack used to install the datadog OCI integration via Quickstart

## Recovering from missing or corrupted Terraform state

`integration_cleanup.py` discovers and removes a Quickstart installation when
the Resource Manager stack can no longer provide reliable Terraform state.
Use it only after the normal Resource Manager destroy flow is unavailable or
has failed.

The cleanup tool requires:

- Python 3.9 or newer.
- A configured OCI CLI identity with permission to inspect and delete the
  Quickstart resources.

This utility removes OCI resources only. Disable or remove the OCI integration
in Datadog before executing cleanup; otherwise the Datadog control plane can
recreate managed connectors, buckets, event rules, or streams.