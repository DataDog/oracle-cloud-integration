"""Responsibility: clean the Datadog VCN, subnet, gateways, and route dependencies.

Safety boundary: validates exact ownership and blocks parents with unapproved nested resources.
Cleanup sequence role: runs after forwarding services and before regional KMS cleanup.

``NetworkMixin.cleanup_network`` dismantles route rules, gateways, subnets, and the
VCN in dependency order, consulting extra-resource approvals before parent removal.
Subnet deletion retries while service-created VNICs detach and records hard blockers.
"""

from __future__ import annotations

import json
import time
from typing import Any

from ..constants import (
    LOGGER,
    NAT_GATEWAY_NAME,
    SERVICE_GATEWAY_NAME,
    SUBNET_NAME,
    SUBNET_VNIC_RETRY_INTERVAL_SECONDS,
    SUBNET_VNIC_RETRY_SECONDS,
    VCN_NAME,
)
from ..errors import CommandError
from ..models import CleanupContext
from ..resources import (
    exact_owned,
    is_owned,
    resource_field,
    resource_id,
    resource_name,
)


class NetworkMixin:
    """Remove the validated Quickstart network and its dependencies."""

    def _block_network_dependents(self, region: str, reason: str) -> None:
        description = (
            "Preserve route tables, gateways, and VCN because "
            f"{reason}"
        )
        self.planned.append(
            {
                "id": f"network-dependents:{region}",
                "description": description,
                "status": "blocked",
            }
        )
        self.manifest.record_action(
            f"network-dependents:{region}",
            description,
            "blocked",
            region=region,
        )
        if self.execute:
            self.manifest.save()

    def cleanup_network(self, context: CleanupContext, region: str) -> None:
        network_extra_kinds = {
            "secondary-vnic",
            "unverified-secondary-vnic",
            "compute-instance",
            "subnet",
            "route-table",
            "nat-gateway",
            "service-gateway",
            "internet-gateway",
            "local-peering-gateway",
        }
        approved_extras_deleted = self._delete_approved_extras(
            region=region, kinds=network_extra_kinds
        )
        network_dependencies_blocked = any(
            candidate.region == region
            and candidate.kind in network_extra_kinds | {"unsupported-vnic"}
            and not self._candidate_is_approved(candidate)
            for candidate in self.extra_candidates
        )
        if not approved_extras_deleted:
            self._block_network_dependents(
                region, "an approved nested-resource deletion failed"
            )
            return
        vcns = self._list_region(
            region,
            [
                "network",
                "vcn",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        owned_vcns = [
            vcn
            for vcn in vcns
            if exact_owned(
                vcn,
                expected_names={VCN_NAME},
                compartment_id=context.compartment_id,
            )
        ]
        owned_vcn_ids = {resource_id(vcn) for vcn in owned_vcns}
        nat_gateways = self._list_region(
            region,
            [
                "network",
                "nat-gateway",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        service_gateways = self._list_region(
            region,
            [
                "network",
                "service-gateway",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        owned_gateway_ids = {
            resource_id(gateway)
            for gateway, expected_name in [
                *[(gateway, NAT_GATEWAY_NAME) for gateway in nat_gateways],
                *[
                    (gateway, SERVICE_GATEWAY_NAME)
                    for gateway in service_gateways
                ],
            ]
            if exact_owned(
                gateway,
                expected_names={expected_name},
                compartment_id=context.compartment_id,
            )
        }
        default_route_table_ids = {
            str(
                resource_field(vcn, "default-route-table-id", "")
            )
            for vcn in owned_vcns
        }
        default_route_table_ids.discard("")

        subnets = self._list_region(
            region,
            [
                "network",
                "subnet",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        for subnet in subnets:
            if not exact_owned(
                subnet,
                expected_names={SUBNET_NAME},
                compartment_id=context.compartment_id,
            ):
                continue
            subnet_id = resource_id(subnet)
            if self._has_unapproved_extra(region=region, container_id=subnet_id):
                action_id = f"subnet:{region}:{subnet_id}"
                description = (
                    f"Preserve Quickstart subnet {subnet_id} because an "
                    "attached resource was not approved or requires manual "
                    "remediation"
                )
                self.planned.append(
                    {
                        "id": action_id,
                        "description": description,
                        "status": "blocked",
                    }
                )
                self.manifest.record_action(
                    action_id,
                    description,
                    "blocked",
                    resource_id=subnet_id,
                    region=region,
                )
                if self.execute:
                    self.manifest.save()
                network_dependencies_blocked = True
                continue
            deleted = self.action(
                f"subnet:{region}:{subnet_id}",
                f"Delete Quickstart subnet {SUBNET_NAME} ({subnet_id}) in {region}",
                function=lambda subnet_id=subnet_id: self._delete_subnet_after_vnic_detach(
                    region, subnet_id
                ),
                details={"resource_id": subnet_id, "region": region},
                retry_completed=True,
            )
            if not deleted:
                network_dependencies_blocked = True

        if network_dependencies_blocked:
            self._block_network_dependents(
                region, "a subnet or nested network dependency remains"
            )
            return

        route_tables = self._list_region(
            region,
            [
                "network",
                "route-table",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        for route_table in route_tables:
            identifier = resource_id(route_table)
            route_table_vcn_id = str(
                resource_field(route_table, "vcn-id", "")
            )
            if route_table_vcn_id not in owned_vcn_ids:
                continue
            name = resource_name(route_table)
            is_default = (
                identifier in default_route_table_ids
                or name == f"Default Route Table for {VCN_NAME}"
            )
            if is_default:
                route_rules = resource_field(route_table, "route-rules", [])
                retained_rules = [
                    rule
                    for rule in route_rules
                    if str(
                        resource_field(rule, "network-entity-id", "")
                    )
                    not in owned_gateway_ids
                ]
                if len(retained_rules) != len(route_rules):
                    self.action(
                        f"route-table-rules:{region}:{identifier}",
                        "Remove Datadog gateway routes from the Quickstart "
                        f"VCN default route table {identifier}",
                        command=[
                            "--region",
                            region,
                            "network",
                            "route-table",
                            "update",
                            "--rt-id",
                            identifier,
                            "--route-rules",
                            json.dumps(retained_rules, separators=(",", ":")),
                            "--force",
                        ],
                        retry_completed=True,
                    )
                continue
            if not is_owned(route_table):
                continue
            self.action(
                f"route-table:{region}:{identifier}",
                f"Delete route table {name} from owned Quickstart VCN",
                command=[
                    "--region",
                    region,
                    "network",
                    "route-table",
                    "delete",
                    "--rt-id",
                    identifier,
                    "--force",
                ],
                retry_completed=True,
            )

        self._delete_owned_list(
            region=region,
            resources=nat_gateways,
            expected_names={NAT_GATEWAY_NAME},
            action_prefix="nat-gateway",
            description="Delete Quickstart NAT gateway",
            command_builder=lambda resource: [
                "--region",
                region,
                "network",
                "nat-gateway",
                "delete",
                "--nat-gateway-id",
                resource_id(resource),
                "--force",
                "--wait-for-state",
                "TERMINATED",
            ],
            compartment_id=context.compartment_id,
            retry_completed=True,
        )

        self._delete_owned_list(
            region=region,
            resources=service_gateways,
            expected_names={SERVICE_GATEWAY_NAME},
            action_prefix="service-gateway",
            description="Delete Quickstart service gateway",
            command_builder=lambda resource: [
                "--region",
                region,
                "network",
                "service-gateway",
                "delete",
                "--service-gateway-id",
                resource_id(resource),
                "--force",
                "--wait-for-state",
                "TERMINATED",
            ],
            compartment_id=context.compartment_id,
            retry_completed=True,
        )

        self._delete_owned_list(
            region=region,
            resources=vcns,
            expected_names={VCN_NAME},
            action_prefix="vcn",
            description="Delete Quickstart VCN",
            command_builder=lambda resource: [
                "--region",
                region,
                "network",
                "vcn",
                "delete",
                "--vcn-id",
                resource_id(resource),
                "--force",
                "--wait-for-state",
                "TERMINATED",
            ],
            compartment_id=context.compartment_id,
            retry_completed=True,
        )

    def _delete_subnet_after_vnic_detach(
        self, region: str, subnet_id: str
    ) -> dict[str, Any]:
        deadline = time.monotonic() + SUBNET_VNIC_RETRY_SECONDS
        command = [
            "--region",
            region,
            "network",
            "subnet",
            "delete",
            "--subnet-id",
            subnet_id,
            "--force",
            "--wait-for-state",
            "TERMINATED",
        ]
        while True:
            try:
                return self.oci.run(
                    command,
                    attempts=3,
                    allow_not_found=True,
                )
            except CommandError as error:
                retryable = (
                    "Conflict" in error.stderr
                    and "references the VNIC" in error.stderr
                )
                remaining = deadline - time.monotonic()
                if not retryable or remaining <= 0:
                    raise
                delay = min(SUBNET_VNIC_RETRY_INTERVAL_SECONDS, remaining)
                LOGGER.warning(
                    "Subnet %s still references a VNIC; retrying deletion in "
                    "%d seconds (up to %d seconds remaining)",
                    subnet_id,
                    round(delay),
                    round(remaining),
                )
                time.sleep(delay)


