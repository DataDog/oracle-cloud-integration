"""Responsibility: schedule secret, key, and vault deletion.

Safety boundary: enforces exact names, ownership, compartment, and OCI minimum delays.
Cleanup sequence role: runs at the end of each regional cleanup sequence.

``KmsMixin`` schedules secret, master-key, and vault deletion. Stable deletion timestamps 
are stored in the manifest so retries reuse the original schedule and preserve the required 
child-before-parent order.
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
from ..resources import exact_owned, lifecycle_state, resource_id


class KmsMixin:
    """Schedule deletion of Quickstart secrets, keys, and vaults."""

    def _deletion_time(self, manifest_key: str, delay: dt.timedelta) -> str:
        with self.manifest.lock:
            existing = self.manifest.data["context"].get(manifest_key)
            if existing:
                return str(existing)
            value = (
                dt.datetime.now(dt.timezone.utc)
                + delay
            ).replace(microsecond=0).isoformat().replace("+00:00", "Z")
            self.manifest.data["context"][manifest_key] = value
            return value

    def cleanup_kms(self, context: CleanupContext, region: str) -> None:
        secret_deletion_time = self._deletion_time(
            "secret_deletion_time", SECRET_DELETION_DELAY
        )
        kms_deletion_time = self._deletion_time(
            "kms_deletion_time", KMS_DELETION_DELAY
        )
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
                details={"deletion_time": secret_deletion_time},
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
            vault_id = resource_id(vault)
            endpoint = str(
                vault.get("management-endpoint")
                or vault.get("management_endpoint")
                or ""
            )
            if not endpoint:
                self.failures.append(
                    f"Owned vault {vault_id} has no management endpoint"
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
                    details={"deletion_time": kms_deletion_time},
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
                    "--endpoint",
                    endpoint,
                    "--vault-id",
                    vault_id,
                    "--time-of-deletion",
                    kms_deletion_time,
                ],
                details={"deletion_time": kms_deletion_time},
            )
            self.kms_pending = True


