"""Responsibility: remove the Datadog-managed tag definition and namespace.

Safety boundary: deletes only the exact expected namespace and marker after IAM succeeds.
Cleanup sequence role: runs after identity cleanup and before parent stack and compartment handling.

``TagsMixin.cleanup_tags`` locates the expected namespace and definition, verifies
their names and ownership evidence, deletes the definition first, and then removes
the now-empty namespace through the shared action recorder.
"""

from __future__ import annotations

from ..constants import LOGGER, TAG_NAME, TAG_NAMESPACE_NAME
from ..models import CleanupContext
from ..resources import exact_owned, resource_id, resource_name


class TagsMixin:
    """Remove the Quickstart tag definition and namespace."""

    def cleanup_tags(self, context: CleanupContext) -> None:
        LOGGER.info("Stage 4/5: cleaning Datadog tag definitions")
        namespaces = self.oci.list(
            [
                "--region",
                context.home_region,
                "iam",
                "tag-namespace",
                "list",
                "--compartment-id",
                context.compartment_id,
                "--include-subcompartments",
                "false",
            ]
        )
        for namespace in namespaces:
            if not exact_owned(
                namespace,
                expected_names={TAG_NAMESPACE_NAME},
                compartment_id=context.compartment_id,
            ):
                continue
            namespace_id = resource_id(namespace)
            tags = self.oci.list(
                [
                    "--region",
                    context.home_region,
                    "iam",
                    "tag",
                    "list",
                    "--tag-namespace-id",
                    namespace_id,
                ]
            )
            for tag in tags:
                if resource_name(tag) != TAG_NAME:
                    continue
                tag_id = resource_id(tag)
                self.action(
                    f"tag-retire:{tag_id}",
                    f"Retire {TAG_NAMESPACE_NAME}.{TAG_NAME}",
                    command=[
                        "--region",
                        context.home_region,
                        "iam",
                        "tag",
                        "retire",
                        "--tag-namespace-id",
                        namespace_id,
                        "--tag-name",
                        TAG_NAME,
                    ],
                )
                self.action(
                    f"tag-delete:{tag_id}",
                    f"Delete {TAG_NAMESPACE_NAME}.{TAG_NAME}",
                    command=[
                        "--region",
                        context.home_region,
                        "iam",
                        "tag",
                        "delete",
                        "--tag-namespace-id",
                        namespace_id,
                        "--tag-name",
                        TAG_NAME,
                        "--force",
                        "--wait-for-state",
                        "SUCCEEDED",
                        "--wait-for-state",
                        "FAILED",
                    ],
                )
            self.action(
                f"tag-namespace-retire:{namespace_id}",
                f"Retire tag namespace {TAG_NAMESPACE_NAME}",
                command=[
                    "--region",
                    context.home_region,
                    "iam",
                    "tag-namespace",
                    "retire",
                    "--tag-namespace-id",
                    namespace_id,
                ],
            )
            self.action(
                f"tag-namespace-delete:{namespace_id}",
                f"Delete tag namespace {TAG_NAMESPACE_NAME}",
                command=[
                    "--region",
                    context.home_region,
                    "iam",
                    "tag-namespace",
                    "delete",
                    "--tag-namespace-id",
                    namespace_id,
                    "--force",
                    "--wait-for-state",
                    "DELETED",
                ],
            )
