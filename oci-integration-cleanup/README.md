# OCI integration cleanup

`integration_cleanup.py` discovers and removes a Datadog OCI Quickstart
installation when Resource Manager can no longer provide reliable Terraform
state. Use it only after the normal stack destroy flow is unavailable or has
failed.

The cleanup tool requires:

- Python 3.9 or newer.
- A configured OCI CLI identity with permission to inspect and delete the
  Quickstart resources.

This utility removes OCI resources only. Disable or remove the OCI integration
in Datadog before executing cleanup; otherwise the Datadog control plane can
recreate managed connectors, buckets, event rules, or streams.
