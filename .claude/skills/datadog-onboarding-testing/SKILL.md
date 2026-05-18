---
name: datadog-onboarding-testing
description: >-
  Manual onboarding test workflow for Datadog OCI integration stacks. Guides
  stack choice (ORM quickstart vs Terraform onboarding), OCI/Datadog prerequisite
  checks, existing-integration detection, local apply or Resource Manager deploy,
  and optional destroy. Use when the user asks to test onboarding, manual stack
  validation, test install, or destroy of datadog-integration /
  datadog-terraform-onboarding.
tools: Bash, Read, Write, Glob, Grep
---

# OCI Datadog Onboarding Testing

Interactive workflow to install and optionally tear down a Datadog OCI stack in a real tenancy. **Use a dedicated test tenancy or compartment** — this creates real OCI resources and a Datadog integration.

## Security rules (always)

- **Never** commit API keys, app keys, or OCIDs into `main.tf`, git, or PRs.
- Read secrets only from environment variables or prompt the user to export them in-shell.
- Create test Terraform under `onboarding-test-runs/<timestamp>/` (gitignored) or `/tmp/datadog-onboarding-test-<timestamp>/`.
- If the user pasted secrets in chat, warn them to rotate and use env vars instead.

## Workflow overview

Copy and track progress:

```
Onboarding test progress:
- [ ] Step 1: Choose stack type
- [ ] Step 2: OCI config + Datadog keys + **confirm site** (default datad0g.com)
- [ ] Step 3: Existing integration check
- [ ] Step 4: Install / apply
- [ ] Step 5: Verify success
- [ ] Step 6: Destroy (optional)
```

---

## Step 1: Choose stack type

Ask the user in chat:

| Option | Path | Deploy method |
|--------|------|----------------|
| **OCI Stack (Quickstart)** | `datadog-integration/` | Zip + `oci resource-manager stack create` in **home region**, **root compartment** |
| **Terraform onboarding** | `datadog-terraform-onboarding/` | Fresh `main.tf` + `terraform init` / `apply` locally |

**Quickstart** = what customers run from Oracle Resource Manager. **Onboarding** = pure Terraform module (no ORM wrapper).

---

## Step 2: Prerequisites

### 2a. OCI CLI config

Verify (don't use `--limit` — it isn't a valid flag for `oci iam region list`):

```bash
test -f ~/.oci/config && oci iam region list >/dev/null 2>&1 && echo "OCI CLI OK" || echo "OCI CLI not configured"
```

If you see a key-file permissions warning, either run `oci setup repair-file-permissions --file <path>` once, or suppress it for the session: `export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True`.

If not configured, instruct the user:

1. Install [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm).
2. Run `oci setup config` and follow prompts (tenancy OCID, user OCID, region, API key).
3. Confirm `~/.oci/config` has a `[DEFAULT]` profile (or note which profile to use: `export OCI_CLI_PROFILE=...`).
4. Ensure the user has IAM rights to create compartments, policies, functions, vault, and Resource Manager stacks in the test tenancy.

Collect (run or ask). Pull `TENANCY_OCID` and `CURRENT_USER_OCID` directly from the config — `oci iam tenancy get` **requires** `--tenancy-id`, so it can't bootstrap itself:

```bash
export TENANCY_OCID=$(awk '/^\[DEFAULT\]/{flag=1; next} /^\[/{flag=0} flag' ~/.oci/config | grep -E '^tenancy=' | cut -d= -f2-)
export CURRENT_USER_OCID=$(awk '/^\[DEFAULT\]/{flag=1; next} /^\[/{flag=0} flag' ~/.oci/config | grep -E '^user=' | cut -d= -f2-)
export HOME_REGION=$(oci iam region-subscription list --tenancy-id "$TENANCY_OCID" \
  --query 'data[?"is-home-region"]."region-name" | [0]' --raw-output)
export ROOT_COMPARTMENT_OCID=$TENANCY_OCID
```

If empty, **ask the user** for their OCI user OCID (`ocid1.user.oc1..`).

Set CLI region to home region for ORM operations:

```bash
export OCI_CLI_REGION=$HOME_REGION
```

### 2b. Datadog API and app keys

Instruct the user to export API and app keys (do not paste values into Terraform files):

```bash
export DATADOG_API_KEY='<api-key>'
export DATADOG_APP_KEY='<app-key>'
```

**Important — env var persistence in Claude Code:** every `! command` invocation and every Claude `Bash` tool call runs in its **own subshell**. Exports do **not** persist across separate invocations. If you'll be running multiple commands (you will), put the exports in a sourced env file and `source` it at the top of every command:

```bash
cat > /tmp/dd-onboarding-test.env <<'EOF'
export DATADOG_API_KEY='<api-key>'
export DATADOG_APP_KEY='<app-key>'
export DATADOG_SITE='datad0g.com'
export TENANCY_OCID='<tenancy-ocid>'
export ROOT_COMPARTMENT_OCID="$TENANCY_OCID"
export HOME_REGION='<home-region>'
export CURRENT_USER_OCID='<user-ocid>'
export OCI_CLI_REGION="$HOME_REGION"
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
EOF
chmod 600 /tmp/dd-onboarding-test.env
```

Then begin every subsequent command with `source /tmp/dd-onboarding-test.env && …`. Delete the file when finished. If the user has already pasted secrets in chat, warn them to rotate the keys — the file is fine to use for the remaining commands, but the chat transcript still has the values.

### 2c. Datadog site (confirm before continuing)

**Default:** `datad0g.com` (Datadog internal/staging site).

**Before setting `DATADOG_SITE` or running any Datadog API calls**, ask the user explicitly:

> Default Datadog site is **datad0g.com**. Use this for onboarding testing? Reply **yes** to confirm, or give another site (e.g. `datadoghq.com`, `datadoghq.eu`, `us3.datadoghq.com`).

- If the user **already stated** a site in this conversation, use that site and **skip** the prompt (but restate which site you are using).
- If they confirm or say nothing else, set:

```bash
export DATADOG_SITE='datad0g.com'
```

- If they name another site, use exactly what they provided.

Verify:

```bash
test -n "$DATADOG_API_KEY" && test -n "$DATADOG_APP_KEY" && test -n "$DATADOG_SITE" && echo "Datadog env OK (site=$DATADOG_SITE)"
```

### 2d. Tools

- `terraform` >= 1.5.0 (onboarding path)
- `oci`, `jq`, `zip`
- Optional: `python3` for integration prechecks in `datadog-integration/`

---

## Step 3: Check for existing integration

Do **both** when possible:

### 3a. Datadog API

The integration list endpoint returns the **tenancy OCID at `.data[].id`** — `.attributes.tenancy_ocid` and `.attributes.name` are `null`. Match on `.id`:

```bash
curl -sS -X GET "https://api.${DATADOG_SITE}/api/v2/integration/oci/tenancies" \
  -H "DD-API-KEY: ${DATADOG_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DATADOG_APP_KEY}" \
  | jq --arg t "$TENANCY_OCID" '.data[]? | select(.id == $t)'
```

If the command prints any object, an integration already exists for this tenancy. Ask whether to continue (may update/fail) or stop and remove the old integration first.

### 3b. OCI (optional)

Ask the user **or** run. Note: the flag is `--compartment-id-in-subtree` (boolean), not `--compartment-id-in-subtree-id`:

```bash
# Datadog compartment (created by stack)
oci iam compartment list --compartment-id "$TENANCY_OCID" --compartment-id-in-subtree true \
  --name "Datadog" --query 'data[].{"id":id,"state":"lifecycle-state","name":name}' --output table

# Resource Manager stacks in root / Datadog compartment (home region)
oci resource-manager stack list --compartment-id "$ROOT_COMPARTMENT_OCID" --region "$HOME_REGION" \
  --all --query 'data[].{"name":"display-name","id":id,"state":"lifecycle-state"}' --output table
```

A leftover `Datadog` compartment without a matching Datadog integration usually means a prior onboarding test run was destroyed Datadog-side but not OCI-side. Creating a new stack will almost certainly fail because the `Datadog` compartment already exists — destroy the old stack first.

If stacks or compartment exist from a prior test, note them for destroy in Step 6.

**Do not proceed** without explicit user acknowledgment if an integration or `Datadog` compartment already exists.

---

## Step 4: Install

### Path A — Terraform onboarding (`datadog-terraform-onboarding`)

1. Create an isolated workspace (repo root = parent of module):

```bash
TEST_DIR="onboarding-test-runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEST_DIR"
```

2. Write **only** `main.tf` (and optional `terraform.tf` if needed). Use env vars — **no literals for secrets**:

```hcl
terraform {
  required_version = ">= 1.5.0"
}

module "datadog_oci" {
  source = "../../datadog-terraform-onboarding"

  datadog_api_key = var.datadog_api_key
  datadog_app_key = var.datadog_app_key
  datadog_site    = var.datadog_site

  tenancy_ocid              = var.tenancy_ocid
  current_user_ocid         = var.current_user_ocid
  resource_compartment_ocid = var.resource_compartment_ocid

  logs_enabled = true   # default; set false only if user explicitly disables logs
}
```

Use a `terraform.tfvars` (gitignored) or `-var` flags — **never** hardcode keys in `main.tf`:

```bash
cat > "$TEST_DIR/terraform.tfvars" <<EOF
datadog_api_key           = "${DATADOG_API_KEY}"
datadog_app_key           = "${DATADOG_APP_KEY}"
datadog_site              = "${DATADOG_SITE}"
tenancy_ocid              = "${TENANCY_OCID}"
current_user_ocid         = "${CURRENT_USER_OCID}"
resource_compartment_ocid = null
EOF
```

Add variables block in `variables.tf` in `$TEST_DIR` or pass `-var` for each. Simpler: use a single `main.tf` with variables and `TF_VAR_*`:

```bash
export TF_VAR_datadog_api_key="$DATADOG_API_KEY"
export TF_VAR_datadog_app_key="$DATADOG_APP_KEY"
export TF_VAR_datadog_site="$DATADOG_SITE"
export TF_VAR_tenancy_ocid="$TENANCY_OCID"
export TF_VAR_current_user_ocid="$CURRENT_USER_OCID"
```

3. Apply:

```bash
cd "$TEST_DIR"
terraform init
terraform apply -auto-approve
```

4. Save `TEST_DIR` path and `terraform.tfstate` location for destroy (record in env file or chat).

**Full variable/template details:** [reference.md](reference.md)

---

### Path B — OCI Stack / Quickstart (`datadog-integration`)

Deploy via Resource Manager using a **local zip** of the module (not the GitHub release URL), in **home region**, **root compartment**.

1. Build zip from repo root:

```bash
cd datadog-integration
zip -rq /tmp/datadog-integration-onboarding-test.zip ./*
```

2. Build stack variables JSON (`logs_enabled` defaults to **`"true"`**; set `LOGS_ENABLED=false` only if the user asks to disable logs):

```bash
LOGS_ENABLED="${LOGS_ENABLED:-true}"
jq -n \
  --arg tenancy_ocid "$TENANCY_OCID" \
  --arg region "$HOME_REGION" \
  --arg compartment_ocid "$ROOT_COMPARTMENT_OCID" \
  --arg current_user_ocid "$CURRENT_USER_OCID" \
  --arg datadog_api_key "$DATADOG_API_KEY" \
  --arg datadog_app_key "$DATADOG_APP_KEY" \
  --arg datadog_site "$DATADOG_SITE" \
  --arg logs_enabled "$LOGS_ENABLED" \
  '{
    tenancy_ocid: $tenancy_ocid,
    region: $region,
    compartment_ocid: $compartment_ocid,
    current_user_ocid: $current_user_ocid,
    datadog_api_key: $datadog_api_key,
    datadog_app_key: $datadog_app_key,
    datadog_site: $datadog_site,
    logs_enabled: $logs_enabled,
    subnet_ocids: "",
    defined_tags: ""
  }' > /tmp/datadog-stack-vars.json
```

3. Create stack and apply (long-running; home region apply waits, regional stacks may continue in background):

```bash
export STACK_DISPLAY_NAME="datadog-onboarding-test-$(date +%Y%m%d-%H%M%S)"
export OCI_CLI_REGION="$HOME_REGION"

STACK_ID=$(oci resource-manager stack create \
  --compartment-id "$ROOT_COMPARTMENT_OCID" \
  --display-name "$STACK_DISPLAY_NAME" \
  --config-source file:///tmp/datadog-integration-onboarding-test.zip \
  --variables file:///tmp/datadog-stack-vars.json \
  --wait-for-state ACTIVE \
  --query 'data.id' --raw-output)

echo "Stack ID: $STACK_ID"

JOB_ID=$(oci resource-manager job create-apply-job \
  --stack-id "$STACK_ID" \
  --execution-plan-strategy AUTO_APPROVED \
  --wait-for-state SUCCEEDED \
  --wait-for-state FAILED \
  --query 'data.id' --raw-output)

oci resource-manager job get --job-id "$JOB_ID" --query 'data.{state:lifecycle-state,message:failure-message}' 
```

4. Record `STACK_ID`, `STACK_DISPLAY_NAME`, `HOME_REGION`, and `ROOT_COMPARTMENT_OCID` for destroy.

**ORM details, troubleshooting, variable list:** [reference.md](reference.md)

---

## Step 5: Verify success

### Onboarding

```bash
terraform output
# Expect integration / compartment / resource outputs per datadog-terraform-onboarding/outputs.tf
```

### Quickstart

```bash
# Apply job succeeded
oci resource-manager job get --job-id "$JOB_ID" --query 'data."lifecycle-state"' --raw-output

# Datadog compartment
oci iam compartment list --compartment-id "$TENANCY_OCID" --compartment-id-in-subtree true --name "Datadog"

# Optional: list functions in a subscribed region (replace region/compartment)
# oci fn application list --compartment-id <datadog-compartment-ocid> --region "$HOME_REGION"
```

Re-run Datadog integration list (Step 3a) and confirm tenancy appears.

Report pass/fail clearly to the user.

---

## Step 6: Destroy (optional)

Ask: **"Destroy the test stack now?"**

### Onboarding

```bash
cd "$TEST_DIR"
terraform destroy -auto-approve
rm -rf "$TEST_DIR"   # after user confirms
```

### Quickstart

```bash
# Destroy via Resource Manager (preferred — runs stack destroy provisioners)
oci resource-manager job create-destroy-job \
  --stack-id "$STACK_ID" \
  --execution-plan-strategy AUTO_APPROVED \
  --wait-for-state SUCCEEDED \
  --wait-for-state FAILED

oci resource-manager stack delete --stack-id "$STACK_ID" --force --wait-for-state DELETED
```

Regional stacks: parent stack destroy should invoke `delete_stack.sh` via Terraform destroy hooks. If regional stacks remain, see `datadog-integration/delete_stack.sh` and [reference.md](reference.md).

Confirm Datadog integration removed (or ask user to delete in UI/API if destroy did not remove it).

---

## Additional resources

- Command reference, ORM variables, destroy edge cases: [reference.md](reference.md)
