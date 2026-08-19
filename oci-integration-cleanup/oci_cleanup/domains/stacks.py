"""Responsibility: destroy regional and explicitly selected parent Resource Manager stacks.

Safety boundary: preserves failed stacks for retry and only accepts constrained stack identities.
Cleanup sequence role: handles regional stacks before orphan services and the parent near the end.

``StacksMixin`` validates region-prefixed child stacks and the selected parent stack,
reconciles Resource Manager destroy jobs, and deletes a stack record only after
OCI reports a successful destroy.
"""

from __future__ import annotations

import datetime as dt
from typing import Any

from ..constants import LOGGER, REGIONAL_STACK_PREFIX
from ..errors import CleanupError
from ..models import CleanupContext
from ..resources import (
    exact_owned,
    is_owned,
    lifecycle_state,
    resource_compartment,
    resource_field,
    resource_id,
    resource_name,
)


class StacksMixin:
    """Destroy validated regional and parent Resource Manager stacks."""

    @staticmethod
    def _job_time(job: dict[str, Any]) -> tuple[int, Any]:
        value = str(resource_field(job, "time-created", "") or "")
        if not value:
            return (0, "")
        try:
            parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=dt.timezone.utc)
            return (2, parsed.timestamp())
        except ValueError:
            return (1, value)

    @staticmethod
    def _job_failure(job: dict[str, Any]) -> tuple[str | None, str]:
        details = resource_field(job, "failure-details", {})
        if not isinstance(details, dict):
            return None, str(details or "")
        code = str(
            resource_field(job, "error-code", "")
            or resource_field(details, "code", "")
            or ""
        )
        message = str(
            resource_field(details, "message", "")
            or resource_field(job, "failure-message", "")
            or ""
        )
        return code or None, message

    def _wait_for_destroy_job(
        self,
        region: str,
        job_id: str,
    ) -> dict[str, Any]:
        result = self.oci.run(
            [
                "--region",
                region,
                "resource-manager",
                "job",
                "get",
                "--job-id",
                job_id,
                "--wait-for-state",
                "SUCCEEDED",
                "--wait-for-state",
                "FAILED",
                "--wait-for-state",
                "CANCELED",
            ],
            attempts=2,
        )
        return result.get("data", result)

    def _create_destroy_job(
        self,
        region: str,
        stack_id: str,
    ) -> dict[str, Any]:
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
        return result.get("data", result)

    def _destroy_stack(
        self,
        region: str,
        stack: dict[str, Any],
        *,
        action_prefix: str,
        stack_kind: str,
        requires_confirmation: bool = False,
    ) -> bool:
        stack_id = resource_id(stack)
        name = resource_name(stack)
        action_id = f"{action_prefix}:{region}:{stack_id}"
        description = f"Destroy and delete {stack_kind} stack {name} ({stack_id})"
        action = {
            "id": action_id,
            "description": description,
            "status": "planned" if not self.execute else "running",
            "resource_id": stack_id,
            "region": region,
            "error_code": None,
            "deletion_message": description,
        }
        if requires_confirmation:
            action["requires_confirmation"] = True
            action["confirmation_reason"] = "missing ownedby=datadog tag"
        self.planned.append(action)
        if not self.execute:
            return True

        try:
            destroy_jobs = [
                job
                for job in self._list_region(
                    region,
                    [
                        "resource-manager",
                        "job",
                        "list",
                        "--stack-id",
                        stack_id,
                    ],
                )
                if str(resource_field(job, "operation", "")).upper() == "DESTROY"
            ]
            newest = max(destroy_jobs, key=self._job_time) if destroy_jobs else None
            state = lifecycle_state(newest or {})
            if newest and state in {"ACCEPTED", "IN_PROGRESS"}:
                job_id = resource_id(newest)
                if not job_id:
                    raise CleanupError(
                        f"Newest {stack_kind} destroy job for {stack_id} has no OCID"
                    )
                job = self._wait_for_destroy_job(region, job_id)
                if lifecycle_state(job) in {"FAILED", "CANCELED", "CANCELLED"}:
                    job = self._create_destroy_job(region, stack_id)
            elif newest and state == "SUCCEEDED":
                job = newest
            elif newest is None or state in {"FAILED", "CANCELED", "CANCELLED"}:
                job = self._create_destroy_job(region, stack_id)
            else:
                job = newest

            final_state = lifecycle_state(job)
            if final_state != "SUCCEEDED":
                error_code, deletion_message = self._job_failure(job)
                failure = self._record_failure(
                    f"{stack_kind.capitalize()} destroy job for {stack_id} "
                    f"ended in {final_state or 'UNKNOWN'}",
                    resource_id=stack_id,
                    region=region,
                    error_code=error_code,
                    deletion_message=deletion_message,
                )
                action["status"] = "failed"
                action["error"] = failure["message"]
                action["error_code"] = failure["error_code"]
                action["deletion_message"] = failure["deletion_message"]
                return False

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
            action["status"] = "completed"
            action["destroy_job_id"] = resource_id(job)
            return True
        except Exception as error:
            # Preserve the stack and its state. Direct orphan cleanup can still
            # proceed, but the failure remains visible and prevents IAM teardown.
            failure = self._record_failure(
                f"{description}: {error}",
                resource_id=stack_id,
                region=region,
                error=error,
            )
            action["status"] = "failed"
            action["error"] = str(error)
            action["error_code"] = failure["error_code"]
            action["deletion_message"] = failure["deletion_message"]
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
            if not name.startswith(REGIONAL_STACK_PREFIX):
                continue
            if resource_compartment(stack) != context.compartment_id:
                continue
            if exact_owned(
                stack,
                expected_names={name},
                compartment_id=context.compartment_id,
            ):
                self.destroy_regional_stack(region, stack)
                continue
            if not self.execute:
                self._destroy_stack(
                    region,
                    stack,
                    action_prefix="regional-stack",
                    stack_kind="regional",
                    requires_confirmation=True,
                )
                continue
            LOGGER.warning(
                "Regional stack %s (%s) in %s has the expected Datadog name "
                "but no ownedby=datadog tag",
                name,
                resource_id(stack),
                region,
            )
            if self._ask_yes_no(f"Delete this untagged regional stack {name}?"):
                self.destroy_regional_stack(region, stack)
            else:
                self._record_failure(
                    "Untagged regional stack deletion was not approved",
                    resource_id=resource_id(stack),
                    region=region,
                )

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
            allow_not_found=True,
        )
        stack = result.get("data", result)
        if not resource_id(stack):
            LOGGER.info(
                "Parent Resource Manager stack %s is already absent",
                self.args.parent_stack_id,
            )
            return
        if not is_owned(stack):
            name = resource_name(stack) or self.args.parent_stack_id
            if not self.execute:
                self._destroy_stack(
                    context.home_region,
                    stack,
                    action_prefix="parent-stack",
                    stack_kind="parent",
                    requires_confirmation=True,
                )
                return
            LOGGER.warning(
                "Explicitly supplied parent stack %s (%s) has no "
                "ownedby=datadog tag",
                name,
                self.args.parent_stack_id,
            )
            if not self._ask_yes_no(f"Delete this untagged parent stack {name}?"):
                self._record_failure(
                    "Untagged parent stack deletion was not approved",
                    resource_id=resource_id(stack),
                    region=context.home_region,
                )
                return
        self._destroy_stack(
            context.home_region,
            stack,
            action_prefix="parent-stack",
            stack_kind="parent",
        )
