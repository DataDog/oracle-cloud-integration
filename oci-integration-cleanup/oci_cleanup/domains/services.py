"""Responsibility: clean connectors, event rules, streams, buckets, and functions.

Safety boundary: retains service-specific names, ownership evidence, waiters, and dependencies.
Cleanup sequence role: removes forwarding services before network and KMS teardown.

``ServicesMixin`` removes connector hubs, event rules, streams, backfill buckets,
functions, and their application using each API's required lookup and delete shape.
Its methods keep producer/consumer and child/application ordering explicit.
"""

from __future__ import annotations

from ..constants import BACKFILL_BUCKET_NAMES, FUNCTION_APP_NAME, FUNCTION_NAMES
from ..errors import CleanupError
from ..models import CleanupContext
from ..resources import (
    defined_marker,
    is_owned,
    resource_compartment,
    resource_id,
    resource_name,
)

SUPPORTED_MANAGED_RESOURCE_PREFIXES = (
    # Buckets, functions, and connectors are recognized here but reconciled by
    # their service-specific cleanup paths.
    "ocid1.bucket.",
    "ocid1.eventrule.",
    "ocid1.fnfunc.",
    "ocid1.serviceconnector.",
    "ocid1.stream.",
)


class ServicesMixin:
    """Remove validated forwarding services and storage resources."""

    def cleanup_connectors_events_streams(
        self, context: CleanupContext, region: str
    ) -> None:
        connectors = self._list_region(
            region,
            [
                "sch",
                "service-connector",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        for connector in connectors:
            if not (is_owned(connector) or defined_marker(connector)):
                continue
            connector_id = resource_id(connector)
            self.action(
                f"connector:{region}:{connector_id}",
                (
                    "Delete Datadog-owned service connector "
                    f"{resource_name(connector)} ({connector_id})"
                ),
                command=[
                    "--region",
                    region,
                    "sch",
                    "service-connector",
                    "delete",
                    "--service-connector-id",
                    connector_id,
                    "--force",
                    "--wait-for-state",
                    "SUCCEEDED",
                    "--wait-for-state",
                    "FAILED",
                ],
            )

        rules = self._list_region(
            region,
            [
                "events",
                "rule",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        deleted_rule_ids: set[str] = set()
        for rule in rules:
            if not (is_owned(rule) or defined_marker(rule)):
                continue
            rule_id = resource_id(rule)
            deleted_rule_ids.add(rule_id)
            self.action(
                f"event-rule:{region}:{rule_id}",
                (
                    "Delete Datadog-owned event rule "
                    f"{resource_name(rule)} ({rule_id})"
                ),
                command=[
                    "--region",
                    region,
                    "events",
                    "rule",
                    "delete",
                    "--rule-id",
                    rule_id,
                    "--force",
                    "--wait-for-state",
                    "DELETED",
                ],
            )

        streams = self._list_region(
            region,
            [
                "streaming",
                "admin",
                "stream",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        deleted_stream_ids: set[str] = set()
        for stream in streams:
            if not (is_owned(stream) or defined_marker(stream)):
                continue
            stream_id = resource_id(stream)
            deleted_stream_ids.add(stream_id)
            self.action(
                f"stream:{region}:{stream_id}",
                (
                    f"Delete Datadog-owned stream {resource_name(stream)} "
                    f"({stream_id})"
                ),
                command=[
                    "--region",
                    region,
                    "streaming",
                    "admin",
                    "stream",
                    "delete",
                    "--stream-id",
                    stream_id,
                    "--force",
                    "--wait-for-state",
                    "SUCCEEDED",
                ],
            )

        # Event rules may live outside the Datadog resource compartment because
        # their IAM grant is tenancy-scoped. Resource Search provides the only
        # tenancy-wide marker lookup, so delete marker-proven rules and streams
        # that the compartment-scoped service lists did not return.
        for resource in context.managed_resources:
            if resource.get("_region") != region or not defined_marker(resource):
                continue
            identifier = resource_id(resource)
            if identifier.startswith("ocid1.eventrule.") and identifier not in deleted_rule_ids:
                self.action(
                    f"event-rule:{region}:{identifier}",
                    (
                        "Delete marker-proven Datadog event rule "
                        f"{resource_name(resource)} ({identifier})"
                    ),
                    command=[
                        "--region",
                        region,
                        "events",
                        "rule",
                        "delete",
                        "--rule-id",
                        identifier,
                        "--force",
                        "--wait-for-state",
                        "DELETED",
                    ],
                )
            elif identifier.startswith("ocid1.stream.") and identifier not in deleted_stream_ids:
                self.action(
                    f"stream:{region}:{identifier}",
                    (
                        "Delete marker-proven Datadog stream "
                        f"{resource_name(resource)} ({identifier})"
                    ),
                    command=[
                        "--region",
                        region,
                        "streaming",
                        "admin",
                        "stream",
                        "delete",
                        "--stream-id",
                        identifier,
                        "--force",
                        "--wait-for-state",
                        "DELETED",
                    ],
                )
            elif not identifier.startswith(SUPPORTED_MANAGED_RESOURCE_PREFIXES):
                message = (
                    "DatadogManaged.marker is attached to unsupported resource "
                    f"{identifier or resource_name(resource)} in {region}; "
                    "manual review required"
                )
                self._record_failure(
                    message,
                    resource_id=identifier,
                    region=region,
                    deletion_message=message,
                )

    def cleanup_buckets(self, context: CleanupContext, region: str) -> None:
        namespace_payload = self.oci.run(
            ["--region", region, "os", "ns", "get"], attempts=2
        )
        namespace = str(namespace_payload.get("data", ""))
        if not namespace:
            raise CleanupError(f"Could not resolve Object Storage namespace in {region}")
        listed_buckets = self._list_region(
            region,
            [
                "os",
                "bucket",
                "list",
                "--compartment-id",
                context.compartment_id,
                "--namespace-name",
                namespace,
            ],
        )
        buckets_by_name = {
            resource_name(bucket): bucket
            for bucket in listed_buckets
            if (
                (is_owned(bucket) or defined_marker(bucket))
                and resource_name(bucket) in BACKFILL_BUCKET_NAMES
            )
        }
        # Marker-proven buckets can live outside the target compartment. Bucket
        # names are unique within an Object Storage namespace, so Resource Search
        # supplies enough information to reconcile them with the regional list.
        for resource in context.managed_resources:
            name = resource_name(resource)
            if (
                resource.get("_region") == region
                and defined_marker(resource)
                and resource_id(resource).startswith("ocid1.bucket.")
                and name in BACKFILL_BUCKET_NAMES
            ):
                buckets_by_name.setdefault(name, resource)

        for bucket in buckets_by_name.values():
            name = resource_name(bucket)
            self.action(
                f"bucket-versions:{region}:{name}",
                f"Delete all object versions from Datadog-owned bucket {name}",
                command=[
                    "--region",
                    region,
                    "os",
                    "object",
                    "bulk-delete-versions",
                    "--namespace-name",
                    namespace,
                    "--bucket-name",
                    name,
                    "--force",
                ],
            )
            self.action(
                f"bucket:{region}:{name}",
                f"Empty and delete Datadog-owned bucket {name}",
                command=[
                    "--region",
                    region,
                    "os",
                    "bucket",
                    "delete",
                    "--namespace-name",
                    namespace,
                    "--bucket-name",
                    name,
                    "--empty",
                    "--force",
                ],
            )

    def cleanup_functions(self, context: CleanupContext, region: str) -> None:
        self._delete_approved_extras(region=region, kinds={"function"})
        handled_function_ids: set[str] = set()
        for application, functions in self._owned_function_applications(
            context, region
        ):
            application_id = resource_id(application)
            for function in functions:
                name = resource_name(function)
                function_id = resource_id(function)
                marker_proven = defined_marker(function) or self._is_managed_function(
                    context, region, function_id
                )
                if not marker_proven and name not in FUNCTION_NAMES:
                    continue
                handled_function_ids.add(function_id)
                self.action(
                    f"function:{region}:{function_id}",
                    f"Delete forwarding function {name}",
                    command=[
                        "--region",
                        region,
                        "fn",
                        "function",
                        "delete",
                        "--function-id",
                        function_id,
                        "--force",
                        "--wait-for-state",
                        "DELETED",
                    ],
                )
            if self._has_unapproved_extra(
                region=region, container_id=application_id
            ):
                self.planned.append(
                    {
                        "id": f"function-app:{region}:{application_id}",
                        "description": (
                            f"Preserve functions application {FUNCTION_APP_NAME} "
                            "because an extra function was not approved"
                        ),
                        "status": "blocked",
                    }
                )
                continue
            self.action(
                f"function-app:{region}:{application_id}",
                f"Delete functions application {FUNCTION_APP_NAME}",
                command=[
                    "--region",
                    region,
                    "fn",
                    "application",
                    "delete",
                    "--application-id",
                    application_id,
                    "--force",
                    "--wait-for-state",
                    "DELETED",
                ],
            )
        for resource in context.managed_resources:
            identifier = resource_id(resource)
            if (
                resource.get("_region") == region
                and resource_compartment(resource) == context.compartment_id
                and identifier.startswith("ocid1.fnfunc.")
                and identifier not in handled_function_ids
            ):
                message = (
                    "Marker-proven Datadog function was not found under the "
                    f"owned {FUNCTION_APP_NAME} application: {identifier} in "
                    f"{region}; manual review required"
                )
                self._record_failure(
                    message,
                    resource_id=identifier,
                    region=region,
                    deletion_message=message,
                )
