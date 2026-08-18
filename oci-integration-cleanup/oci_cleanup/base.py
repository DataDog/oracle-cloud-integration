"""Responsibility: shared in-memory action state and owned-list helpers.

Safety boundary: centralizes the dry-run gate before any mutation.
Cleanup sequence role: underpins every discovery and deletion stage.

``CleanupBase.action`` is the single mutation checkpoint: it records dry runs and
executes approved commands. Its list helpers also apply ownership and compartment
checks before bulk deletion.
"""

from __future__ import annotations

import argparse
from typing import Any, Callable, Optional

from .constants import LOGGER
from .models import ExtraResourceCandidate
from .oci import OciCli
from .resources import (
    defined_marker,
    is_owned,
    resource_compartment,
    resource_id,
    resource_name,
)


class CleanupBase:
    """Shared action execution and ownership helpers."""

    def __init__(
        self,
        args: argparse.Namespace,
        oci: OciCli,
    ):
        self.args = args
        self.oci = oci
        self.execute = args.execute
        self.planned: list[dict[str, Any]] = []
        self.failures: list[dict[str, Any]] = []
        self.kms_pending = False
        self.extra_candidates: list[ExtraResourceCandidate] = []
        self.approved_extra_ids: set[str] = set()
        self._accessible_compartment_ids: Optional[list[str]] = None

    def action(
        self,
        action_id: str,
        description: str,
        command: Optional[list[str]] = None,
        function: Optional[Callable[[], Any]] = None,
        details: Optional[dict[str, Any]] = None,
    ) -> bool:
        entry = {
            "id": action_id,
            "description": description,
            "status": "planned" if not self.execute else "running",
            "resource_id": "",
            "region": "",
            "error_code": None,
            "deletion_message": description,
            **(details or {}),
        }
        self.planned.append(entry)
        if not self.execute:
            LOGGER.info("Planned: %s", description)
            return True

        LOGGER.info("Executing: %s", description)
        try:
            if function:
                function()
            elif command:
                self.oci.run(command, attempts=3, allow_not_found=True)
            entry["status"] = "completed"
            LOGGER.info("Completed: %s", description)
            return True
        except Exception as error:
            failure = self._record_failure(
                f"{description}: {error}",
                resource_id=str((details or {}).get("resource_id") or ""),
                region=str((details or {}).get("region") or ""),
                error=error,
            )
            entry["status"] = "failed"
            entry["error"] = str(error)
            entry["error_code"] = failure["error_code"]
            entry["deletion_message"] = failure["deletion_message"]
            LOGGER.error("Failed: %s: %s", description, error)
            return False

    def _record_failure(
        self,
        message: str,
        *,
        resource_id: str = "",
        region: str = "",
        error: Optional[Exception] = None,
        error_code: Optional[str] = None,
        deletion_message: str = "",
    ) -> dict[str, Any]:
        """Record a consistently shaped failure for summaries and callers."""

        failure = {
            "message": message,
            "resource_id": resource_id,
            "region": region or str(getattr(error, "region", "") or ""),
            "error_code": (
                str(error_code or getattr(error, "code", "") or "") or None
            ),
            "deletion_message": (
                deletion_message
                or str(getattr(error, "service_message", "") or "")
                or (str(error) if error else message)
            ),
        }
        self.failures.append(failure)
        return failure


    def _list_region(
        self, region: str, service_args: list[str]
    ) -> list[dict[str, Any]]:
        return self.oci.list(["--region", region, *service_args])

    def _delete_owned_list(
        self,
        *,
        region: str,
        resources: list[dict[str, Any]],
        expected_names: set[str],
        action_prefix: str,
        description: str,
        command_builder: Callable[[dict[str, Any]], list[str]],
        compartment_id: str,
        allow_marker: bool = False,
    ) -> None:
        for resource in resources:
            name = resource_name(resource)
            ownership = is_owned(resource) or (allow_marker and defined_marker(resource))
            if (
                not ownership
                or name not in expected_names
                or (
                    resource_compartment(resource)
                    and resource_compartment(resource) != compartment_id
                )
            ):
                continue
            identifier = resource_id(resource)
            self.action(
                f"{action_prefix}:{region}:{identifier}",
                f"{description} {name} ({identifier}) in {region}",
                command=command_builder(resource),
                details={"resource_id": identifier, "region": region},
            )


