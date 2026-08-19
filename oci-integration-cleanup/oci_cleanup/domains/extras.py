"""Responsibility: discover, confirm, and delete unexpected nested resources.

Safety boundary: fails closed for non-interactive input and keeps approvals in-session.
Cleanup sequence role: runs after discovery and before concurrent regional cleanup.

``ExtrasMixin`` finds unexpected functions, VNIC attachments, and network dependents within 
the Datadog created function apps and VCN resources and
turns each into an auditable candidate command, and prompts on every execute run
while the blocker remains live. Later stages use the current run's decisions to
delete approved children or preserve their parents.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from typing import Any, Optional

from ..constants import (
    FUNCTION_APP_NAME,
    FUNCTION_NAMES,
    LOGGER,
    NAT_GATEWAY_NAME,
    SERVICE_GATEWAY_NAME,
    SUBNET_NAME,
    VCN_NAME,
)
from ..errors import CommandError
from ..models import CleanupContext, ExtraResourceCandidate
from ..resources import (
    data_items,
    defined_marker,
    exact_owned,
    is_deleted_or_deleting,
    is_owned,
    lifecycle_state,
    resource_compartment,
    resource_field,
    resource_id,
    resource_name,
)


@dataclass(frozen=True)
class _GatewaySpec:
    kind: str
    cli_kind: str
    id_flag: str
    expected_owned_name: Optional[str]
    always_extra: bool


class ExtrasMixin:
    """Manage approval and deletion of unexpected nested resources."""

    def _extra_candidate(
        self,
        *,
        kind: str,
        resource: dict[str, Any],
        region: str,
        container_id: str,
        container_name: str,
        impact: str,
        command: Optional[list[str]],
        resource_identifier: Optional[str] = None,
        resource_display_name: Optional[str] = None,
        requires_compute_confirmation: bool = False,
        details: Optional[dict[str, Any]] = None,
    ) -> ExtraResourceCandidate:
        identifier = resource_identifier or resource_id(resource)
        return ExtraResourceCandidate(
            candidate_id=f"extra:{kind}:{region}:{identifier}",
            kind=kind,
            resource_id=identifier,
            name=resource_display_name or resource_name(resource) or identifier,
            region=region,
            container_id=container_id,
            container_name=container_name,
            impact=impact,
            command=tuple(command) if command else None,
            requires_compute_confirmation=requires_compute_confirmation,
            details=details or {},
        )


    def _compute_compartment_ids(self, context: CleanupContext) -> list[str]:
        if self._accessible_compartment_ids is not None:
            return self._accessible_compartment_ids
        compartments: list[dict[str, Any]] = []
        try:
            compartments = self._list_region(
                context.home_region,
                [
                    "iam",
                    "compartment",
                    "list",
                    "--compartment-id",
                    context.tenancy_id,
                    "--compartment-id-in-subtree",
                    "true",
                    "--access-level",
                    "ACCESSIBLE",
                ],
            )
        except CommandError as error:
            LOGGER.warning(
                "Could not inventory accessible compartments for cross-compartment "
                "VNIC attachment discovery: %s",
                error,
            )
            return list(
                dict.fromkeys([context.compartment_id, context.tenancy_id])
            )
        identifiers = [
            resource_id(compartment)
            for compartment in compartments
            if resource_id(compartment)
            and lifecycle_state(compartment) not in {"DELETED", "DELETING"}
        ]
        identifiers.extend([context.compartment_id, context.tenancy_id])
        self._accessible_compartment_ids = list(dict.fromkeys(identifiers))
        return self._accessible_compartment_ids

    def _find_vnic_attachments(
        self,
        context: CleanupContext,
        region: str,
        vnic_id: str,
        preferred_compartment_id: str,
    ) -> tuple[list[dict[str, Any]], str]:
        compartment_ids = [
            preferred_compartment_id,
            *self._compute_compartment_ids(context),
        ]
        for compartment_id in dict.fromkeys(
            identifier for identifier in compartment_ids if identifier
        ):
            try:
                attachments = self._list_region(
                    region,
                    [
                        "compute",
                        "vnic-attachment",
                        "list",
                        "--compartment-id",
                        compartment_id,
                        "--vnic-id",
                        vnic_id,
                    ],
                )
            except CommandError as error:
                LOGGER.warning(
                    "Could not inspect VNIC %s attachments in compartment %s: %s",
                    vnic_id,
                    compartment_id,
                    error,
                )
                continue
            live_attachments = [
                attachment
                for attachment in attachments
                if lifecycle_state(attachment) not in {"DETACHED", "DETACHING"}
            ]
            if live_attachments:
                return live_attachments, compartment_id
        return [], ""

    def _discover_vnic_extras(
        self,
        context: CleanupContext,
        region: str,
        subnet: dict[str, Any],
    ) -> list[ExtraResourceCandidate]:
        subnet_id = resource_id(subnet)
        payload = self.oci.run(
            [
                "--region",
                region,
                "search",
                "resource",
                "structured-search",
                "--query-text",
                f"query Vnic resources where subnetId = '{subnet_id}'",
            ],
            attempts=2,
        )
        candidates: list[ExtraResourceCandidate] = []
        for search_vnic in data_items(payload):
            vnic_id = resource_id(search_vnic)
            if not vnic_id:
                continue
            vnic_payload = self.oci.run(
                [
                    "--region",
                    region,
                    "network",
                    "vnic",
                    "get",
                    "--vnic-id",
                    vnic_id,
                ],
                attempts=2,
                allow_not_found=True,
            )
            vnic = vnic_payload.get("data", vnic_payload)
            if not vnic or str(
                resource_field(vnic, "subnet-id", "")
            ) != subnet_id:
                continue
            vnic_compartment = resource_compartment(vnic)
            attachments, instance_compartment = self._find_vnic_attachments(
                context,
                region,
                vnic_id,
                vnic_compartment,
            )
            attachment = attachments[0] if len(attachments) == 1 else None
            instance_id = str(
                resource_field(attachment or {}, "instance-id", "")
            )
            primary_value = (
                vnic.get("is-primary")
                if "is-primary" in vnic
                else vnic.get("is_primary")
            )
            is_primary = (
                primary_value
                if isinstance(primary_value, bool)
                else str(primary_value).lower() == "true"
            )
            if not attachment or not instance_id:
                detach_command = (
                    [
                        "--region",
                        region,
                        "compute",
                        "instance",
                        "detach-vnic",
                        "--compartment-id",
                        vnic_compartment,
                        "--vnic-id",
                        vnic_id,
                        "--force",
                        "--wait-for-state",
                        "DETACHED",
                    ]
                    if vnic_compartment
                    else None
                )
                candidates.append(
                    self._extra_candidate(
                        kind=(
                            "unverified-secondary-vnic"
                            if detach_command
                            else "unsupported-vnic"
                        ),
                        resource=vnic,
                        region=region,
                        container_id=subnet_id,
                        container_name=SUBNET_NAME,
                        impact=(
                            "The VNIC owner could not be identified. If approved, "
                            "the script will attempt OCI's secondary Compute VNIC "
                            "detach operation. OCI will reject the request if this "
                            "is a primary or service-managed VNIC."
                        ),
                        command=detach_command,
                        details={"vnic_id": vnic_id},
                    )
                )
                continue
            instance_payload = self.oci.run(
                [
                    "--region",
                    region,
                    "compute",
                    "instance",
                    "get",
                    "--instance-id",
                    instance_id,
                ],
                attempts=2,
                allow_not_found=True,
            )
            instance = instance_payload.get("data", instance_payload)
            if is_primary:
                candidates.append(
                    self._extra_candidate(
                        kind="compute-instance",
                        resource=instance or {"id": instance_id},
                        region=region,
                        container_id=subnet_id,
                        container_name=SUBNET_NAME,
                        impact=(
                            "This is the primary VNIC. Deleting the dependency "
                            "terminates the entire Compute instance; its boot "
                            "volume will be preserved."
                        ),
                        command=[
                            "--region",
                            region,
                            "compute",
                            "instance",
                            "terminate",
                            "--instance-id",
                            instance_id,
                            "--preserve-boot-volume",
                            "true",
                            "--force",
                            "--wait-for-state",
                            "SUCCEEDED",
                        ],
                        resource_identifier=instance_id,
                        requires_compute_confirmation=True,
                        details={"vnic_id": vnic_id, "instance_id": instance_id},
                    )
                )
            else:
                candidates.append(
                    self._extra_candidate(
                        kind="secondary-vnic",
                        resource=vnic,
                        region=region,
                        container_id=subnet_id,
                        container_name=SUBNET_NAME,
                        impact=(
                            "The secondary VNIC will be detached and deleted "
                            "from its Compute instance."
                        ),
                        command=[
                            "--region",
                            region,
                            "compute",
                            "instance",
                            "detach-vnic",
                            "--compartment-id",
                            instance_compartment,
                            "--vnic-id",
                            vnic_id,
                            "--force",
                            "--wait-for-state",
                            "DETACHED",
                        ],
                        details={"vnic_id": vnic_id, "instance_id": instance_id},
                    )
                )
        primary_instances = {
            candidate.resource_id
            for candidate in candidates
            if candidate.kind == "compute-instance"
        }
        return [
            candidate
            for candidate in candidates
            if candidate.kind != "secondary-vnic"
            or candidate.details.get("instance_id") not in primary_instances
        ]

    def _discover_network_extras(
        self, context: CleanupContext, region: str
    ) -> list[ExtraResourceCandidate]:
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
        candidates: list[ExtraResourceCandidate] = []
        for vcn in owned_vcns:
            vcn_id = resource_id(vcn)
            default_route_table_id = str(
                resource_field(vcn, "default-route-table-id", "")
            )
            subnets = self._list_region(
                region,
                [
                    "network",
                    "subnet",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                    "--vcn-id",
                    vcn_id,
                ],
            )
            for subnet in subnets:
                if is_deleted_or_deleting(subnet):
                    continue
                if exact_owned(
                    subnet,
                    expected_names={SUBNET_NAME},
                    compartment_id=context.compartment_id,
                ):
                    candidates.extend(
                        self._discover_vnic_extras(context, region, subnet)
                    )
                    continue
                candidates.append(
                    self._extra_candidate(
                        kind="subnet",
                        resource=subnet,
                        region=region,
                        container_id=vcn_id,
                        container_name=VCN_NAME,
                        impact=(
                            "Deleting this subnet may be required before the "
                            "owned VCN can be deleted."
                        ),
                        command=[
                            "--region",
                            region,
                            "network",
                            "subnet",
                            "delete",
                            "--subnet-id",
                            resource_id(subnet),
                            "--force",
                            "--wait-for-state",
                            "TERMINATED",
                        ],
                    )
                )
            route_tables = self._list_region(
                region,
                [
                    "network",
                    "route-table",
                    "list",
                    "--compartment-id",
                    context.compartment_id,
                    "--vcn-id",
                    vcn_id,
                ],
            )
            for route_table in route_tables:
                if is_deleted_or_deleting(route_table):
                    continue
                identifier = resource_id(route_table)
                if identifier == default_route_table_id or is_owned(route_table):
                    continue
                candidates.append(
                    self._extra_candidate(
                        kind="route-table",
                        resource=route_table,
                        region=region,
                        container_id=vcn_id,
                        container_name=VCN_NAME,
                        impact=(
                            "Deleting this route table may be required before "
                            "the owned VCN can be deleted."
                        ),
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
                    )
                )
            gateway_specs = [
                _GatewaySpec(
                    "nat-gateway",
                    "nat-gateway",
                    "--nat-gateway-id",
                    NAT_GATEWAY_NAME,
                    False,
                ),
                _GatewaySpec(
                    "service-gateway",
                    "service-gateway",
                    "--service-gateway-id",
                    SERVICE_GATEWAY_NAME,
                    False,
                ),
                _GatewaySpec(
                    "internet-gateway",
                    "internet-gateway",
                    "--ig-id",
                    None,
                    True,
                ),
                _GatewaySpec(
                    "local-peering-gateway",
                    "local-peering-gateway",
                    "--local-peering-gateway-id",
                    None,
                    True,
                ),
            ]
            for spec in gateway_specs:
                gateways = self._list_region(
                    region,
                    [
                        "network",
                        spec.cli_kind,
                        "list",
                        "--compartment-id",
                        context.compartment_id,
                        "--vcn-id",
                        vcn_id,
                    ],
                )
                for gateway in gateways:
                    if is_deleted_or_deleting(gateway):
                        continue
                    if not spec.always_extra and exact_owned(
                        gateway,
                        expected_names={spec.expected_owned_name or ""},
                        compartment_id=context.compartment_id,
                    ):
                        continue
                    candidates.append(
                        self._extra_candidate(
                            kind=spec.kind,
                            resource=gateway,
                            region=region,
                            container_id=vcn_id,
                            container_name=VCN_NAME,
                            impact=(
                                "Deleting this gateway may be required before "
                                "the owned VCN can be deleted."
                            ),
                            command=[
                                "--region",
                                region,
                                "network",
                                spec.cli_kind,
                                "delete",
                                spec.id_flag,
                                resource_id(gateway),
                                "--force",
                                "--wait-for-state",
                                "TERMINATED",
                            ],
                        )
                    )
        return candidates

    def discover_extra_resources(
        self, context: CleanupContext
    ) -> list[ExtraResourceCandidate]:
        LOGGER.info("Discovering extra resources inside owned Datadog containers")
        candidates: dict[str, ExtraResourceCandidate] = {}
        for region in context.regions:
            discovered = self._discover_network_extras(context, region)
            for candidate in discovered:
                candidates[candidate.candidate_id] = candidate
        return sorted(
            candidates.values(),
            key=lambda candidate: (
                candidate.region,
                candidate.container_name,
                candidate.kind,
                candidate.resource_id,
            ),
        )

    def _ask_yes_no(self, prompt: str) -> bool:
        stream = sys.stdin
        if not stream.isatty():
            LOGGER.warning("%s [y/n]: no interactive TTY; defaulting to n", prompt)
            return False
        while True:
            print(f"{prompt} [y/n]: ", end="", file=sys.stderr, flush=True)
            answer = stream.readline()
            if not answer:
                LOGGER.warning("Input ended; defaulting to n")
                return False
            normalized = answer.strip().lower()
            if normalized == "y":
                return True
            if normalized == "n":
                return False
            print("Please answer y or n.", file=sys.stderr)

    def prepare_extra_resource_cleanup(self, context: CleanupContext) -> None:
        self.extra_candidates = self.discover_extra_resources(context)
        for candidate in self.extra_candidates:
            review = {
                "id": f"review:{candidate.candidate_id}",
                "description": (
                    f"Review extra {candidate.kind} {candidate.name} "
                    f"({candidate.resource_id}) in {candidate.region}"
                ),
                "status": "confirmation-required",
                "resource_id": candidate.resource_id,
                "resource_type": candidate.kind,
                "region": candidate.region,
                "error_code": None,
                "deletion_message": (
                    f"Delete extra {candidate.kind} {candidate.resource_id}"
                ),
                "container_id": candidate.container_id,
                "container_name": candidate.container_name,
                "impact": candidate.impact,
            }
            self.planned.append(review)
            if not candidate.command:
                review["status"] = "unsupported"
                LOGGER.warning(
                    "Blocked resource requires manual remediation:\n"
                    "  type: %s\n  name: %s\n  OCID: %s\n  region: %s\n"
                    "  Datadog container: %s (%s)\n  impact: %s\n"
                    "  reason: no verified service-specific deletion handler",
                    candidate.kind,
                    candidate.name,
                    candidate.resource_id,
                    candidate.region,
                    candidate.container_name,
                    candidate.container_id,
                    candidate.impact,
                )
                message = (
                    f"Extra {candidate.kind} {candidate.resource_id} in "
                    f"{candidate.container_name} cannot be safely deleted automatically"
                )
                self._record_failure(
                    message,
                    resource_id=candidate.resource_id,
                    region=candidate.region,
                    deletion_message=message,
                )
                continue
            if not self.execute:
                continue
            LOGGER.warning(
                "Blocked resource found:\n"
                "  type: %s\n  name: %s\n  OCID: %s\n  region: %s\n"
                "  Datadog container: %s (%s)\n  impact: %s",
                candidate.kind,
                candidate.name,
                candidate.resource_id,
                candidate.region,
                candidate.container_name,
                candidate.container_id,
                candidate.impact,
            )
            approved = self._ask_yes_no(
                f"Delete this blocked {candidate.kind} resource?"
            )
            if approved and candidate.requires_compute_confirmation:
                LOGGER.warning(
                    "COMPUTE INSTANCE WARNING: this permanently terminates "
                    "instance %s. The boot volume will be preserved.",
                    candidate.resource_id,
                )
                approved = self._ask_yes_no(
                    f"Terminate Compute instance {candidate.resource_id}?"
                )
            if approved:
                self.approved_extra_ids.add(candidate.candidate_id)
                review["status"] = "approved"
            else:
                review["status"] = "declined"
                message = (
                    f"Extra {candidate.kind} {candidate.resource_id} was not "
                    "approved for deletion"
                )
                self._record_failure(
                    message,
                    resource_id=candidate.resource_id,
                    region=candidate.region,
                    deletion_message=message,
                )

    def _candidate_is_approved(self, candidate: ExtraResourceCandidate) -> bool:
        return candidate.candidate_id in self.approved_extra_ids

    def _has_unapproved_extra(
        self, *, region: str, container_id: str
    ) -> bool:
        return any(
            candidate.region == region
            and candidate.container_id == container_id
            and not self._candidate_is_approved(candidate)
            for candidate in self.extra_candidates
        )

    def _delete_approved_extras(
        self, *, region: str, kinds: set[str]
    ) -> bool:
        priorities = {
            "secondary-vnic": 0,
            "unverified-secondary-vnic": 0,
            "compute-instance": 0,
            "function": 0,
            "subnet": 1,
            "route-table": 2,
            "nat-gateway": 3,
            "service-gateway": 3,
            "internet-gateway": 3,
            "local-peering-gateway": 3,
        }
        candidates = sorted(
            (
                candidate
                for candidate in self.extra_candidates
                if candidate.region == region
                and candidate.kind in kinds
                and self._candidate_is_approved(candidate)
            ),
            key=lambda candidate: (
                priorities.get(candidate.kind, 100),
                candidate.candidate_id,
            ),
        )
        succeeded = True
        for candidate in candidates:
            assert candidate.command is not None
            if not self.action(
                candidate.candidate_id,
                f"Delete approved extra {candidate.kind} {candidate.name} "
                f"({candidate.resource_id}) in {region}",
                command=list(candidate.command),
                details={
                    "approved_extra": True,
                    "resource_id": candidate.resource_id,
                    "region": region,
                    "container_id": candidate.container_id,
                },
            ):
                succeeded = False
        return succeeded


