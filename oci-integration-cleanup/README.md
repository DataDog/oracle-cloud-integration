# OCI integration cleanup

## Usage

Use an OCI CLI profile whose `tenancy` identifies the installation tenancy.
The profile defaults to `DEFAULT`; select another with `--profile`.

Always review a dry run first:

```bash
python3 oci-integration-cleanup/integration_cleanup.py \
  --profile "$OCI_PROFILE" \
  --compartment-ocid "$COMPARTMENT_OCID" \
  --dry-run true
```

Execute after reviewing the inventory:

```bash
python3 oci-integration-cleanup/integration_cleanup.py \
  --profile "$OCI_PROFILE" \
  --compartment-ocid "$COMPARTMENT_OCID" \
  --confirm-tenancy-id "$TENANCY_OCID" \
  --region-workers 1 \
  --dry-run false
```

`--compartment-ocid` is optional when discovery identifies exactly one target
compartment. Discovery only queries tenancy subscriptions that are also home or
replica regions of the profile user's Identity Domain. Use `--domain-ocid` when
the installation belongs to a different domain. Add `--parent-stack-id` to
destroy the parent Resource Manager stack. Add `--delete-compartment` only when the proven
Quickstart-created compartment should also be removed. Use `--oci-bin` or
`OCI_BIN` when the OCI CLI is not available as `oci` on `PATH`.

Rerun the same command to retry resources that remain live.
