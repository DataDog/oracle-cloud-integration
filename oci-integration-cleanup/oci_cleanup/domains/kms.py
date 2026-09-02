"""Responsibility: schedule secret, key, and vault deletion.

Safety boundary: enforces exact names, ownership, compartment, and OCI minimum delays.
Cleanup sequence role: runs at the end of each regional cleanup sequence.

``KmsMixin`` schedules active secrets, master keys, and vaults with timestamps computed
for the current run. Resources already pending deletion are left to OCI, while active
children are always scheduled before their parent vault.
"""

from __future__ import annotations

import datetime as dt

from ..constants import (
    KEY_NAME,
    KMS_DELETION_DELAY,
    SECRET_DELETION_DELAY,
    SECRET_NAME,
    VAULT_NAME,
)
from ..models import CleanupContext
from ..resources import (
    exact_owned,
    lifecycle_state,
    resource_id,
    resource_management_endpoint,
)


class KmsMixin:
    """Schedule active Quickstart secrets, keys, and vaults for deletion."""

    @staticmethod
    def _deletion_time(delay: dt.timedelta) -> str:
        """Return a fresh OCI deletion timestamp valid for this cleanup run."""

        return (
            dt.datetime.now(dt.timezone.utc) + delay
        ).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    def cleanup_kms(self, context: CleanupContext, region: str) -> None:
        """Schedule active owned KMS resources using run-local timestamps."""

        secret_deletion_time = self._deletion_time(SECRET_DELETION_DELAY)
        kms_deletion_time = self._deletion_time(KMS_DELETION_DELAY)
        secrets = self._list_region(
            region,
            [
                "vault",
                "secret",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        for secret in secrets:
            if not exact_owned(
                secret,
                expected_names={SECRET_NAME},
                compartment_id=context.compartment_id,
            ):
                continue
            if lifecycle_state(secret) == "PENDING_DELETION":
                self.kms_pending = True
                continue
            if lifecycle_state(secret) != "ACTIVE":
                continue
            identifier = resource_id(secret)
            self.action(
                f"secret:{region}:{identifier}",
                f"Schedule deletion of {SECRET_NAME} in {region}",
                command=[
                    "--region",
                    region,
                    "vault",
                    "secret",
                    "schedule-secret-deletion",
                    "--secret-id",
                    identifier,
                    "--time-of-deletion",
                    secret_deletion_time,
                ],
                details={
                    "deletion_time": secret_deletion_time,
                    "resource_id": identifier,
                    "region": region,
                },
            )
            self.kms_pending = True

        vaults = self._list_region(
            region,
            [
                "kms",
                "management",
                "vault",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        for vault in vaults:
            if not exact_owned(
                vault,
                expected_names={VAULT_NAME},
                compartment_id=context.compartment_id,
            ):
                continue
            if lifecycle_state(vault) == "PENDING_DELETION":
                self.kms_pending = True
                continue
            if lifecycle_state(vault) != "ACTIVE":
                continue
            vault_id = resource_id(vault)
            endpoint = resource_management_endpoint(vault)
            if not endpoint:
                self._record_failure(
                    f"Owned vault {vault_id} in {region} has no management endpoint",
                    resource_id=vault_id,
                    region=region,
                )
                continue
            keys = self.oci.list(
                [
                    "--region",
                    region,
                    "kms",
                    "management",
                    "key",
                    "list",
                    "--endpoint",
                    endpoint,
                    "--compartment-id",
                    context.compartment_id,
                ]
            )
            for key in keys:
                if not exact_owned(
                    key,
                    expected_names={KEY_NAME},
                    compartment_id=context.compartment_id,
                ):
                    continue
                if lifecycle_state(key) == "PENDING_DELETION":
                    self.kms_pending = True
                    continue
                if lifecycle_state(key) not in {"ACTIVE", "ENABLED"}:
                    continue
                key_id = resource_id(key)
                self.action(
                    f"kms-key:{region}:{key_id}",
                    f"Schedule deletion of {KEY_NAME} in {region}",
                    command=[
                        "--region",
                        region,
                        "kms",
                        "management",
                        "key",
                        "schedule-deletion",
                        "--endpoint",
                        endpoint,
                        "--key-id",
                        key_id,
                        "--time-of-deletion",
                        kms_deletion_time,
                    ],
                    details={
                        "deletion_time": kms_deletion_time,
                        "resource_id": key_id,
                        "region": region,
                    },
                )
                self.kms_pending = True
            self.action(
                f"kms-vault:{region}:{vault_id}",
                f"Schedule deletion of {VAULT_NAME} in {region}",
                command=[
                    "--region",
                    region,
                    "kms",
                    "management",
                    "vault",
                    "schedule-deletion",
                    "--vault-id",
                    vault_id,
                    "--time-of-deletion",
                    kms_deletion_time,
                ],
                details={
                    "deletion_time": kms_deletion_time,
                    "resource_id": vault_id,
                    "region": region,
                },
            )
            self.kms_pending = True
