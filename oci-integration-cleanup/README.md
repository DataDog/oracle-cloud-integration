# OCI integration cleanup

This directory contains the recovery tool for removing a Datadog OCI
Quickstart installation when Resource Manager state is missing, corrupted, or
no longer describes all installed resources. Use the normal Resource Manager
destroy flow when its Terraform state is still usable.

The tool removes OCI resources only. Disable or remove the OCI integration in
Datadog before running execute mode; otherwise the Datadog control plane can
recreate managed connectors, buckets, event rules, or streams.

Development is split across a stacked PR series. This README describes the
completed tool; intermediate PRs contain only the modules enabled at that layer
of the stack.

## Files

- `integration_cleanup.py` is the executable entry point and stable public
  import facade. It parses arguments, enforces tenancy confirmation, loads the
  state file, and assembles the `QuickstartCleanup` engine from focused mixins.
- `oci_cleanup/engine.py` controls the complete cleanup sequence.
- `oci_cleanup/discovery.py` discovers subscribed regions, the home region,
  identity domains, the target compartment, ownership tags, and managed
  resources.
- `oci_cleanup/region.py` defines the dependency order used in every region
  and isolates one region's errors from other regional workers.
- `oci_cleanup/base.py` provides the common dry-run and mutation gate used by
  every deletion action.
- `oci_cleanup/manifest.py` stores resumable action state, approvals, deletion
  timestamps, results, and full error diagnostics.
- `oci_cleanup/oci.py` invokes the OCI CLI and normalizes paginated responses.
- `oci_cleanup/errors.py` converts OCI failures into concise service,
  operation, region, and customer-action messages.
- `oci_cleanup/resources.py` contains ownership, lifecycle, name, and response
  normalization helpers.
- `oci_cleanup/constants.py` and `oci_cleanup/models.py` define known
  Quickstart identities and shared data structures.
- `oci_cleanup/domains/extras.py` discovers unexpected resources nested inside
  Datadog-owned containers and handles interactive approval.
- `oci_cleanup/domains/stacks.py` destroys regional stacks and, after regional
  cleanup succeeds, the explicitly selected parent stack.
- `oci_cleanup/domains/services.py` removes service connectors, event rules,
  streams, backfill buckets, functions, and function applications.
- `oci_cleanup/domains/network.py` removes VNIC dependencies, subnets, route
  rules and tables, gateways, and VCNs in dependency order.
- `oci_cleanup/domains/kms.py` schedules API-key secret, KMS key, and vault
  deletion using OCI's required delays.
- `oci_cleanup/domains/identity.py` removes validated API keys, users, groups,
  dynamic groups, and policies.
- `oci_cleanup/domains/tags.py` removes the Datadog managed tag and namespace.
- `oci_cleanup/domains/compartment.py` validates residual resources and
  optionally deletes a proven Quickstart-created compartment.
- `tests/test_integration_cleanup.py` covers the public facade, safety gates,
  ownership checks, dependency order, resumability, and service-specific
  cleanup.

## Cleanup flow

The runtime call chain is:

1. `integration_cleanup.py` parses the command line, assembles
   `QuickstartCleanup`, and calls its `run()` method.
2. `oci_cleanup/engine.py` provides `EngineMixin.run()`, the top-level
   orchestrator.
3. The engine delegates installation discovery to
   `oci_cleanup/discovery.py`, then blocker discovery and approval to
   `oci_cleanup/domains/extras.py`.
4. The engine starts the regional workers. Each worker delegates the ordered
   regional cleanup sequence to `oci_cleanup/region.py`.
5. After every region finishes, the engine either preserves tenancy-wide
   resources because failures remain or proceeds with final teardown.

### 1. Validate the invocation

`integration_cleanup.py` manages the arguments and is the main runner for the
cleanup program. It assembles the focused cleanup mixins into
`QuickstartCleanup`, constructs the OCI and manifest adapters, and calls
`EngineMixin.run()`. Dry-run mode requires only the tenancy OCID. Execute mode
additionally requires:

- `--confirm-tenancy-id` to exactly match `--tenancy-id`.
- `--state-file` a desired path to a state file to persist progress in the case of script failures.
- A configured OCI CLI identity with permission to inspect and delete resources.

`oci_cleanup/manifest.py` rejects an existing state file if it belongs to a
different tenancy.

### 2. Discover and validate ownership

`EngineMixin.run()` first delegates to `oci_cleanup/discovery.py`, which lists
READY region subscriptions, resolves the home region, and searches every region
for:

- The freeform tag `ownedby=datadog`.
- The defined tag `DatadogManaged.marker=true`.

It then resolves the target compartment and refuses to continue if discovered
resources indicate multiple possible compartments. Supplying
`--compartment-id` resolves an otherwise ambiguous installation, but it must
not conflict with tagged resource evidence.

### 3. Find nested blockers and request approval

After installation discovery, the engine delegates to
`oci_cleanup/domains/extras.py`. Before regional deletion begins, it inspects
Datadog-owned function applications and networking containers for unexpected
functions, VNICs, subnets, route tables, or gateways.

Dry-run mode reports these resources without prompting. Execute mode asks for
`y` or `n` before deleting each supported extra resource. Primary VNIC cleanup
requires a second confirmation because it terminates the owning Compute
instance while preserving its boot volume. Non-interactive input fails closed,
and unsupported resources are reported for manual remediation.

### 4. Clean each region

The engine processes regions in parallel with the configured
`--region-workers` value. Every worker calls `oci_cleanup/region.py`, which
applies this order inside its region:

1. `domains/stacks.py` starts a Resource Manager destroy job for a validated
   regional stack and deletes the stack record only after the job succeeds.
   This runs first so Resource Manager can use its Terraform state before the
   service-specific cleanup removes any orphaned resources.
2. `domains/services.py` removes service connectors, event rules, streams,
   backfill buckets, functions, and function applications.
3. `domains/network.py` detaches approved VNICs, removes subnets, strips gateway
   route rules, deletes non-default route tables, deletes gateways, and finally
   deletes the VCN.
4. `domains/kms.py` schedules deletion of `DatadogAPIKey`, then `datadog-key`,
   then `datadog-vault`.

A regional failure is recorded without stopping workers in other regions.
OCI throttling can be reduced by rerunning with `--region-workers 1`.

### 5. Complete tenancy-wide teardown

`oci_cleanup/engine.py` treats unresolved regional failures as a safety
barrier. If any failure remains, IAM, tags, the parent stack, and the optional
compartment are preserved so a later run can retry safely.

When regional cleanup succeeds:

1. `domains/identity.py` removes only IAM resources whose expected identity,
   ownership, descriptions, rules, and policy references are validated.
2. `domains/tags.py` removes the Datadog marker tag and namespace.
3. `domains/stacks.py` destroys the explicitly supplied parent stack.
4. `domains/compartment.py` deletes the compartment only when
   `--delete-compartment` was supplied and no residual resources, child
   compartments, or pending KMS resources remain.

The parent stack remains near the end because all regional child stacks and
regional resources must be settled first. Optional compartment deletion remains
the final destructive step.

OCI secrets require a delayed deletion, and KMS keys and vaults require at
least a seven-day delay. The state file preserves their scheduled timestamps,
so later runs reuse the same schedule.

### 6. Resume safely

Every mutation passes through `oci_cleanup/base.py`. Successful actions are
recorded in `oci_cleanup/manifest.py` and skipped on later runs unless OCI still
lists the resource. Failed and blocked actions remain retryable.

Customer-facing output contains a concise service and operation summary. The
state file retains the complete OCI command output and request ID under
`raw_error` for troubleshooting.

## Usage

Always review a dry run first:

```bash
python3 oci-integration-cleanup/integration_cleanup.py \
  --tenancy-id "$TENANCY_OCID" \
  --compartment-id "$COMPARTMENT_OCID"
```

Execute after reviewing the inventory:

```bash
python3 oci-integration-cleanup/integration_cleanup.py \
  --tenancy-id "$TENANCY_OCID" \
  --compartment-id "$COMPARTMENT_OCID" \
  --confirm-tenancy-id "$TENANCY_OCID" \
  --state-file ./datadog-cleanup-state.json \
  --region-workers 1 \
  --execute
```

Use the same command and state file to resume. Add `--parent-stack-id` when the
parent Resource Manager stack should be destroyed. Add `--delete-compartment`
only when the proven Quickstart-created compartment should also be removed.

Run the tests with:

```bash
python3 -m unittest discover \
  -s oci-integration-cleanup/tests \
  -p 'test_*.py' \
  -v
```
