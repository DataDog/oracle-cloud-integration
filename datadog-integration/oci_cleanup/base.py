"""Responsibility: shared engine state, action recording, and owned-list helpers.

Safety boundary: centralizes dry-run and manifest gates before any mutation.
Cleanup sequence role: underpins every discovery and deletion stage.

``CleanupBase.action`` is the single mutation checkpoint: it skips completed
manifest actions, records dry runs, executes approved commands, and persists outcomes.
Its list helpers also apply ownership and compartment checks before bulk deletion.
"""

from __future__ import annotations

import argparse
from typing import Any, Callable, Optional

from .constants import LOGGER
from .errors import raw_error_message
from .manifest import Manifest
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
        manifest: Manifest,
    ):
        self.args = args
        self.oci = oci
        self.manifest = manifest
        self.execute = args.execute
        self.planned: list[dict[str, Any]] = []
        self.failures: list[str] = []
        self.kms_pending = False
        self.extra_candidates: list[ExtraResourceCandidate] = []
        self.approved_extra_ids: set[str] = set()
        self._accessible_compartment_ids: Optional[list[str]] = None

    def _read_action(
        self, action_id: str, description: str, function: Callable[[], Any]
    ) -> Any:
        try:
            return function()
        except Exception as error:
            message = f"{description}: {error}"
            self.manifest.record_error(
                message,
                action_id,
                raw_error=raw_error_message(error),
            )
            raise

    def action(
        self,
        action_id: str,
        description: str,
        command: Optional[list[str]] = None,
        function: Optional[Callable[[], Any]] = None,
        details: Optional[dict[str, Any]] = None,
        retry_completed: bool = False,
    ) -> bool:
        if self.manifest.completed(action_id) and not retry_completed:
            LOGGER.info("Skipping completed action: %s", description)
            self.planned.append(
                {
                    "id": action_id,
                    "description": description,
                    "status": "already-completed",
                }
            )
            return True
        if self.manifest.completed(action_id):
            LOGGER.warning(
                "Retrying completed action because OCI still lists the resource: %s",
                description,
            )

        entry = {
            "id": action_id,
            "description": description,
            "status": "planned" if not self.execute else "running",
            **(details or {}),
        }
        self.planned.append(entry)
        if not self.execute:
            LOGGER.info("Planned: %s", description)
            self.manifest.record_action(action_id, description, "planned", **(details or {}))
            return True

        LOGGER.info("Executing: %s", description)
        self.manifest.record_action(action_id, description, "running", **(details or {}))
        self.manifest.save()
        try:
            if function:
                result = function()
            elif command:
                result = self.oci.run(
                    command, attempts=3, allow_not_found=True
                )
            else:
                result = None
            self.manifest.record_action(
                action_id,
                description,
                "completed",
                result=result if isinstance(result, (dict, list, str, int)) else None,
                **(details or {}),
            )
            self.manifest.save()
            entry["status"] = "completed"
            LOGGER.info("Completed: %s", description)
            return True
        except Exception as error:
            message = f"{description}: {error}"
            raw_error = raw_error_message(error)
            self.failures.append(message)
            self.manifest.record_action(
                action_id,
                description,
                "failed",
                error=str(error),
                raw_error=raw_error,
                **(details or {}),
            )
            self.manifest.record_error(
                message,
                action_id,
                raw_error=raw_error,
            )
            self.manifest.save()
            entry["status"] = "failed"
            entry["error"] = str(error)
            LOGGER.error("Failed: %s: %s", description, error)
            return False


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
        retry_completed: bool = False,
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
                retry_completed=retry_completed,
            )


