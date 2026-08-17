"""Responsibility: destroy regional and explicitly selected parent Resource Manager stacks.

Safety boundary: preserves failed stacks for retry and only accepts constrained stack identities.
Cleanup sequence role: handles regional stacks before orphan services and the parent near the end.

``StacksMixin`` validates region-prefixed child stacks and the selected parent stack,
starts Resource Manager destroy jobs, and checks terminal job status. A stack is
recorded complete only after a successful destroy, leaving failures resumable.
"""

from __future__ import annotations

from typing import Any

from ..constants import LOGGER, REGIONAL_STACK_PREFIX
from ..errors import CleanupError, raw_error_message
from ..models import CleanupContext
from ..resources import (
    exact_owned,
    is_owned,
    lifecycle_state,
    resource_id,
    resource_name,
)


class StacksMixin:
    """Destroy validated regional and parent Resource Manager stacks."""

    def _destroy_stack(
        self,
        region: str,
        stack: dict[str, Any],
        *,
        action_prefix: str,
        stack_kind: str,
    ) -> bool:
        stack_id = resource_id(stack)
        name = resource_name(stack)
        action_id = f"{action_prefix}:{region}:{stack_id}"
        description = f"Destroy and delete {stack_kind} stack {name} ({stack_id})"
        if self.manifest.completed(action_id):
            return True
        self.planned.append(
            {
                "id": action_id,
                "description": description,
                "status": "planned" if not self.execute else "running",
            }
        )
        if not self.execute:
            self.manifest.record_action(action_id, description, "planned")
            return True

        self.manifest.record_action(action_id, description, "running")
        self.manifest.save()
        try:
            result = self.oci.run(
                [
                    "--region",
                    region,
                    "resource-manager",
                    "job",
                    "create-destroy-job",
                    "--stack-id",
                    stack_id,
                    "--execution-plan-strategy",
                    "AUTO_APPROVED",
                    "--wait-for-state",
                    "SUCCEEDED",
                    "--wait-for-state",
                    "FAILED",
                ],
                attempts=2,
            )
            job = result.get("data", result)
            state = lifecycle_state(job)
            if state != "SUCCEEDED":
                raise CleanupError(
                    f"{stack_kind.capitalize()} destroy job for {stack_id} "
                    f"ended in {state or 'UNKNOWN'}"
                )
            self.oci.run(
                [
                    "--region",
                    region,
                    "resource-manager",
                    "stack",
                    "delete",
                    "--stack-id",
                    stack_id,
                    "--force",
                    "--wait-for-state",
                    "DELETED",
                ],
                attempts=2,
                allow_not_found=True,
            )
            self.manifest.record_action(
                action_id,
                description,
                "completed",
                destroy_job_id=resource_id(job),
            )
            self.manifest.save()
            return True
        except Exception as error:
            # Preserve the stack and its state. Direct orphan cleanup can still
            # proceed, but the failure remains visible and prevents IAM teardown.
            message = f"{description}: {error}"
            raw_error = raw_error_message(error)
            self.failures.append(message)
            self.manifest.record_action(
                action_id,
                description,
                "failed",
                error=str(error),
                raw_error=raw_error,
            )
            self.manifest.record_error(
                message,
                action_id,
                raw_error=raw_error,
            )
            self.manifest.save()
            return False

    def destroy_regional_stack(
        self, region: str, stack: dict[str, Any]
    ) -> bool:
        return self._destroy_stack(
            region,
            stack,
            action_prefix="regional-stack",
            stack_kind="regional",
        )

    def cleanup_regional_stacks(
        self, context: CleanupContext, region: str
    ) -> None:
        stacks = self._list_region(
            region,
            [
                "resource-manager",
                "stack",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        for stack in stacks:
            name = resource_name(stack)
            if name.startswith(REGIONAL_STACK_PREFIX) and exact_owned(
                stack,
                expected_names={name},
                compartment_id=context.compartment_id,
            ):
                self.destroy_regional_stack(region, stack)


    def cleanup_parent_stack(self, context: CleanupContext) -> None:
        if not self.args.parent_stack_id:
            return
        LOGGER.info("Checking explicitly supplied parent Resource Manager stack")
        result = self.oci.run(
            [
                "--region",
                context.home_region,
                "resource-manager",
                "stack",
                "get",
                "--stack-id",
                self.args.parent_stack_id,
            ],
            attempts=2,
        )
        stack = result.get("data", result)
        if not is_owned(stack):
            LOGGER.warning(
                "Preserving explicitly supplied parent stack %s because it "
                "does not have the ownedby=datadog tag",
                self.args.parent_stack_id,
            )
            return
        self._destroy_stack(
            context.home_region,
            stack,
            action_prefix="parent-stack",
            stack_kind="parent",
        )
