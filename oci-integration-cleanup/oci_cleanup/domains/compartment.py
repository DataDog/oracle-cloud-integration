"""Responsibility: inspect residual resources and optionally delete the Datadog compartment.

Safety boundary: requires proven auto-creation, explicit opt-in, and an empty safe residual scan.
Cleanup sequence role: performs the final resource-container cleanup.

``CompartmentMixin`` inventories supported OCI resource families across the target
and nested compartments, distinguishing ignorable terminal objects from blockers.
It deletes the compartment only when discovery evidence and the residual scan agree.
"""

from __future__ import annotations

from typing import Any

from ..constants import AUTO_COMPARTMENT_DESCRIPTION, AUTO_COMPARTMENT_NAME, LOGGER
from ..errors import CleanupError
from ..models import CleanupContext
from ..resources import data_items, is_owned, lifecycle_state, resource_id, resource_name


class CompartmentMixin:
    """Inspect residuals and safely delete the target compartment."""

    def _safe_list(
        self,
        context: CleanupContext,
        region: str,
        service_args: list[str],
        error_key: str,
        error_prefix: str = "Inventory failed",
    ) -> list[dict[str, Any]]:
        try:
            resources = self._list_region(region, service_args)
            return [dict(resource, _region=region) for resource in resources]
        except Exception as error:
            return [
                {
                    "id": f"inventory-error:{region}:{error_key}",
                    "display-name": f"{error_prefix}: {error}",
                    "resource-type": "InventoryError",
                    "compartment-id": context.compartment_id,
                    "_region": region,
                }
            ]

    def compartment_residuals(
        self, context: CleanupContext
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        children = self.oci.list(
            [
                "--region",
                context.home_region,
                "iam",
                "compartment",
                "list",
                "--compartment-id",
                context.compartment_id,
                "--compartment-id-in-subtree",
                "false",
            ]
        )
        children = [
            child
            for child in children
            if lifecycle_state(child) not in {"DELETED", "DELETING"}
        ]

        residuals: list[dict[str, Any]] = []
        namespace = ""
        try:
            namespace_payload = self.oci.run(
                [
                    "--region",
                    context.home_region,
                    "os",
                    "ns",
                    "get",
                ],
                attempts=2,
            )
            namespace = str(namespace_payload.get("data", ""))
            if not namespace:
                raise CleanupError("Object Storage namespace was empty")
        except Exception as error:
            residuals.append(
                {
                    "id": "inventory-error:object-storage-namespace",
                    "display-name": f"Object Storage namespace lookup failed: {error}",
                    "resource-type": "InventoryError",
                    "compartment-id": context.compartment_id,
                    "_region": context.home_region,
                }
            )

        for region in context.regions:
            payload = self.oci.run(
                [
                    "--region",
                    region,
                    "search",
                    "resource",
                    "structured-search",
                    "--query-text",
                    f"query all resources where compartmentId = "
                    f"'{context.compartment_id}'",
                ],
                attempts=2,
            )
            for resource in data_items(payload):
                copy = dict(resource)
                copy["_region"] = region
                residuals.append(copy)

            # Resource Search is eventually consistent and does not cover every
            # service equally. Re-list the services touched by cleanup so a
            # missed or untagged resource blocks compartment deletion.
            service_lists = [
                [
                    "resource-manager",
                    "stack",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "sch",
                    "service-connector",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "events",
                    "rule",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "streaming",
                    "admin",
                    "stream",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "fn",
                    "application",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "network",
                    "subnet",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "network",
                    "vcn",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "network",
                    "nat-gateway",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "network",
                    "service-gateway",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "vault",
                    "secret",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
                [
                    "kms",
                    "management",
                    "vault",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                ],
            ]
            for service_args in service_lists:
                for resource in self._safe_list(
                    context,
                    region,
                    service_args,
                    "-".join(service_args[:3]),
                ):
                    if lifecycle_state(resource) not in {
                        "DELETED",
                        "DELETING",
                        "TERMINATED",
                        "TERMINATING",
                    }:
                        residuals.append(resource)

            if not namespace:
                continue
            bucket_args = [
                "os",
                "bucket",
                "list",
                "--compartment-id",
                context.compartment_id,
                "--namespace-name",
                namespace,
            ]
            residuals.extend(
                self._safe_list(
                    context,
                    region,
                    bucket_args,
                    "object-storage",
                    "Object Storage inventory failed",
                )
            )
        unique: dict[str, dict[str, Any]] = {}
        for resource in residuals:
            identifier = resource_id(resource)
            if identifier and identifier != context.compartment_id:
                unique[identifier] = resource
        return list(unique.values()), children

    def delete_compartment(self, context: CleanupContext) -> None:
        if not self.args.delete_compartment:
            LOGGER.info("Compartment deletion was not requested")
            return
        LOGGER.info("Stage 5/5: validating optional compartment deletion")
        if not context.compartment:
            self.failures.append(
                "Compartment deletion requested, but the target compartment was "
                "not proven to be Quickstart-created and tagged"
            )
            return
        if (
            resource_name(context.compartment) != AUTO_COMPARTMENT_NAME
            or str(context.compartment.get("description", ""))
            not in {"", AUTO_COMPARTMENT_DESCRIPTION}
            or not is_owned(context.compartment)
        ):
            self.failures.append(
                "Compartment deletion requested, but ownership/name/description "
                "validation failed"
            )
            return
        if not self.execute:
            self.action(
                f"compartment:{context.compartment_id}",
                (
                    "Conditionally delete the Quickstart-created compartment "
                    "after post-cleanup service inventories prove it is empty"
                ),
                command=[
                    "--region",
                    context.home_region,
                    "iam",
                    "compartment",
                    "delete",
                    "--compartment-id",
                    context.compartment_id,
                    "--force",
                ],
                details={
                    "conditional": True,
                    "requires_no_children": True,
                    "requires_no_residual_resources": True,
                    "requires_no_pending_kms": True,
                },
            )
            return
        residuals, children = self.compartment_residuals(context)
        if residuals or children or self.kms_pending:
            self.failures.append(
                "Compartment preserved: "
                f"{len(residuals)} residual resources, {len(children)} child "
                f"compartments, kms_pending={self.kms_pending}"
            )
            self.manifest.data["compartment_blockers"] = {
                "resources": [
                    {
                        "id": resource_id(resource),
                        "name": resource_name(resource),
                        "type": resource.get("resource-type")
                        or resource.get("resource_type"),
                        "region": resource.get("_region"),
                        "owned": is_owned(resource),
                    }
                    for resource in residuals
                ],
                "child_compartments": [
                    {
                        "id": resource_id(child),
                        "name": resource_name(child),
                    }
                    for child in children
                ],
                "kms_pending": self.kms_pending,
            }
            if self.execute:
                self.manifest.save()
            return
        self.action(
            f"compartment:{context.compartment_id}",
            f"Delete empty Quickstart-created compartment {context.compartment_id}",
            command=[
                "--region",
                context.home_region,
                "iam",
                "compartment",
                "delete",
                "--compartment-id",
                context.compartment_id,
                "--force",
                "--wait-for-state",
                "SUCCEEDED",
                "--wait-for-state",
                "FAILED",
            ],
        )
