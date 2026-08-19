"""Responsibility: define shared discovery context and extra-resource candidates.

Safety boundary: stores evidence and commands but does not execute them.
Cleanup sequence role: passes validated state between discovery, confirmation, and cleanup.

``CleanupContext`` carries tenancy, region, compartment, domain, tag, and stack
discovery results through every stage. ``ExtraResourceCandidate`` pairs an unexpected
resource with its proposed deletion command and the reason confirmation is required.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

@dataclass
class CleanupContext:
    tenancy_id: str
    home_region: str
    regions: list[str]
    compartment_id: str
    compartment: Optional[dict[str, Any]]
    domains: list[dict[str, Any]]
    tagged_resources: list[dict[str, Any]]
    managed_resources: list[dict[str, Any]] = field(default_factory=list)


@dataclass(frozen=True)
class ExtraResourceCandidate:
    candidate_id: str
    kind: str
    resource_id: str
    name: str
    region: str
    container_id: str
    container_name: str
    impact: str
    command: Optional[tuple[str, ...]] = None
    requires_compute_confirmation: bool = False
    details: dict[str, Any] = field(default_factory=dict)
