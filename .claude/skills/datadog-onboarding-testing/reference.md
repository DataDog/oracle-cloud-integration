# OCI Datadog Onboarding Testing — Reference

## Terraform onboarding — minimal file set

`onboarding-test-runs/<id>/variables.tf`:

```hcl
variable "datadog_api_key" { type = string sensitive = true }
variable "datadog_app_key" { type = string sensitive = true }
variable "datadog_site" { type = string }
variable "tenancy_ocid" { type = string }
variable "current_user_ocid" { type = string }
variable "resource_compartment_ocid" {
  type    = string
  default = null
}
```

`main.tf` — set `source` relative to `onboarding-test-runs/<id>/` (usually `../../datadog-terraform-onboarding`).

Apply with `TF_VAR_*` exports or `-var-file=terraform.tfvars` (add `*.tfvars` to `.gitignore` in the test dir).

**Duration:** multi-region; can take 30–90+ minutes depending on subscribed regions.

---

## ORM quickstart — stack variables JSON

Required variables for `datadog-integration` (match `schema.yaml` / `variables.tf`):

| Variable | Source |
|----------|--------|
| `tenancy_ocid` | `$TENANCY_OCID` |
| `region` | `$HOME_REGION` |
| `compartment_ocid` | `$ROOT_COMPARTMENT_OCID` (where RM stack lives) |
| `current_user_ocid` | `$CURRENT_USER_OCID` |
| `datadog_api_key` | `$DATADOG_API_KEY` |
| `datadog_app_key` | `$DATADOG_APP_KEY` |
| `datadog_site` | `$DATADOG_SITE` (default `datad0g.com`; confirm with user unless they specified another site) |
| `logs_enabled` | `"true"` by default (ORM schema uses string; set `"false"` only if user asks to disable logs) |
| `subnet_ocids` | `""` (default VCN per region) |
| `compartment_id` | `""` or null (creates `Datadog` compartment) |
| `defined_tags` | `""` unless testing tags |

Example `/tmp/datadog-stack-vars.json`:

```json
{
  "tenancy_ocid": "ocid1.tenancy.oc1..aaaa...",
  "region": "us-ashburn-1",
  "compartment_ocid": "ocid1.tenancy.oc1..aaaa...",
  "current_user_ocid": "ocid1.user.oc1..aaaa...",
  "datadog_api_key": "REDACTED",
  "datadog_app_key": "REDACTED",
  "datadog_site": "datad0g.com",
  "logs_enabled": "true",
  "subnet_ocids": "",
  "defined_tags": ""
}
```

**Important:** Stack must run in **home region**. `compartment_ocid` for the RM stack is typically the **tenancy root** for onboarding tests.

---

## Build integration zip

Same layout as release workflow:

```bash
cd datadog-integration
zip -r /tmp/datadog-integration-onboarding-test.zip ./*
```

Exclude nothing required by prechecks (`pre_check.py`, `docker_image_check.sh`, modules, etc.).

---

## Datadog API — list / delete integration

List:

```http
GET https://api.${DATADOG_SITE}/api/v2/integration/oci/tenancies
DD-API-KEY: ...
DD-APPLICATION-KEY: ...
```

Delete (if user confirms — **destructive**):

```http
DELETE https://api.${DATADOG_SITE}/api/v2/integration/oci/tenancies/{integration_id}
```

Use only when cleaning a failed test; confirm with user.

---

## OCI — find leftover resources

| Resource | Command hint |
|----------|----------------|
| Datadog compartment | `oci iam compartment list --name Datadog` |
| Parent RM stack | `oci resource-manager stack list --compartment-id $ROOT_COMPARTMENT_OCID` |
| Regional stacks | Name prefix `datadog-regional-stack-` in each region |
| Functions app | `oci fn application list` in Datadog compartment |
| Dynamic groups | `oci identity dynamic-group list` filter display name `dd-functions` |

---

## Destroy — regional stacks manual cleanup

If parent destroy did not clean regionals:

```bash
# From repo root; args: compartment_ocid region stack_display_name [defined_tags_json]
./datadog-integration/delete_stack.sh <COMPARTMENT_OCID> <REGION> "datadog-regional-stack-<digest>"
```

Digest matches `terraform_data.stack_digest.id` from parent apply (check RM job logs or Terraform state).

---

## Common failures

| Symptom | Likely cause |
|---------|----------------|
| Precheck / docker image check fails | OCIR images `oci-datadog-forwarder` not available in region |
| Identity domain errors | No active domain or user not in domain |
| Apply job FAILED on home region | Insufficient IAM, quota, or invalid subnet OCIDs |
| Regional jobs not waited | By design — only home region waits; check other regions in Console |
| `go mod` / unrelated | N/A for stack onboarding tests |

---

## `~/.oci/config` example

```ini
[DEFAULT]
user=ocid1.user.oc1..aaaa...
fingerprint=xx:xx:...
tenancy=ocid1.tenancy.oc1..aaaa...
region=us-ashburn-1
key_file=~/.oci/oci_api_key.pem
```

`region` should match home region for ORM stack operations (`OCI_CLI_REGION`).
