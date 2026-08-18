"""Responsibility: tenancy, region, compartment, domain, and ownership discovery.

Safety boundary: requires unambiguous compartment evidence before cleanup proceeds.
Cleanup sequence role: runs first and produces the validated cleanup context.

``DiscoveryMixin.discover`` resolves the home region, subscribed regions, identity
domains, target compartment, ownership-tagged resources, and relevant stacks.
Regional tag searches run concurrently and are consolidated into ``CleanupContext``.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

from .constants import AUTO_COMPARTMENT_NAME, LOGGER
from .errors import CleanupError
from .models import CleanupContext
from .resources import (
    data_items,
    is_owned,
    resource_compartment,
    resource_id,
    resource_name,
    resource_type,
)


class DiscoveryMixin:
    """Discover and validate the cleanup context."""

    def _discover_region_tags(
        self, region: str
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        LOGGER.info("Searching ownership tags in region %s", region)
        payload = self.oci.run(
            [
                "--region",
                region,
                "search",
                "resource",
                "structured-search",
                "--query-text",
                "query all resources where "
                "(freeformTags.key = 'ownedby' && "
                "freeformTags.value = 'datadog')",
            ],
            attempts=2,
        )
        marker_payload = self.oci.run(
            [
                "--region",
                region,
                "search",
                "resource",
                "structured-search",
                "--query-text",
                "query all resources where "
                "(definedTags.namespace = 'DatadogManaged' && "
                "definedTags.key = 'marker' && "
                "definedTags.value = 'true')",
            ],
            attempts=2,
        )
        tagged = [{**resource, "_region": region} for resource in data_items(payload)]
        managed = [
            {**resource, "_region": region}
            for resource in data_items(marker_payload)
        ]
        return tagged, managed

    def discover(self) -> CleanupContext:
        LOGGER.info("Stage 1/5: discovering tenancy and subscribed regions")
        subscriptions = self.oci.list(
            ["iam", "region-subscription", "list", "--tenancy-id", self.args.tenancy_id]
        )
        active = [
            subscription
            for subscription in subscriptions
            if str(subscription.get("status", "READY")).upper() == "READY"
        ]
        if not active:
            raise CleanupError("No READY OCI region subscriptions were found")
        regions = sorted(
            {
                str(item.get("region-name") or item.get("region_name"))
                for item in active
                if item.get("region-name") or item.get("region_name")
            }
        )
        if not regions:
            raise CleanupError("READY OCI subscriptions had no region names")
        home_regions = [
            str(item.get("region-name") or item.get("region_name"))
            for item in active
            if item.get("is-home-region") or item.get("is_home_region")
        ]
        if len(home_regions) != 1:
            raise CleanupError(f"Expected one home region, found {home_regions}")
        home_region = home_regions[0]
        LOGGER.info(
            "Discovered home region %s and %d subscribed region(s)",
            home_region,
            len(regions),
        )

        tagged: list[dict[str, Any]] = []
        managed: list[dict[str, Any]] = []
        worker_count = min(self.args.region_workers, len(regions))
        if worker_count == 1:
            results = (self._discover_region_tags(region) for region in regions)
            for region_tagged, region_managed in results:
                tagged.extend(region_tagged)
                managed.extend(region_managed)
        else:
            with ThreadPoolExecutor(
                max_workers=worker_count,
                thread_name_prefix="oci-discovery",
            ) as executor:
                futures = [
                    executor.submit(self._discover_region_tags, region)
                    for region in regions
                ]
                for future in as_completed(futures):
                    region_tagged, region_managed = future.result()
                    tagged.extend(region_tagged)
                    managed.extend(region_managed)

        compartment_candidates: set[str] = set()
        auto_compartments = [
            resource
            for resource in tagged
            if resource_name(resource) == AUTO_COMPARTMENT_NAME
            and "compartment" in resource_type(resource).lower()
            and is_owned(resource)
        ]
        compartment_candidates.update(
            resource_id(resource) for resource in auto_compartments if resource_id(resource)
        )
        # Workload resources share the selected Datadog compartment. Tenancy-level
        # policies and the compartment resource itself are excluded as signals.
        for resource in tagged:
            compartment_id = resource_compartment(resource)
            kind = resource_type(resource).lower()
            if (
                compartment_id
                and compartment_id != self.args.tenancy_id
                and "policy" not in kind
                and "compartment" not in kind
            ):
                compartment_candidates.add(compartment_id)

        explicit_signal = self.args.compartment_id or ""
        if explicit_signal:
            if compartment_candidates and explicit_signal not in compartment_candidates:
                raise CleanupError(
                    f"Resolved compartment {explicit_signal} conflicts with tagged "
                    f"resource compartments {sorted(compartment_candidates)}"
                )
            compartment_id = explicit_signal
        elif len(compartment_candidates) == 1:
            compartment_id = next(iter(compartment_candidates))
        elif not compartment_candidates:
            raise CleanupError(
                "Could not resolve the Datadog compartment. Supply --compartment-id."
            )
        else:
            raise CleanupError(
                f"Multiple candidate compartments found: "
                f"{sorted(compartment_candidates)}. Supply --compartment-id."
            )
        LOGGER.info("Resolved target compartment %s", compartment_id)

        matching_auto = [
            resource
            for resource in auto_compartments
            if resource_id(resource) == compartment_id
        ]
        compartment = matching_auto[0] if matching_auto else None

        domains = self.oci.list(
            [
                "--region",
                home_region,
                "iam",
                "domain",
                "list",
                "--compartment-id",
                self.args.tenancy_id,
            ]
        )
        if self.args.domain_endpoint:
            domains = [
                {
                    "url": self.args.domain_endpoint,
                    "display-name": "explicit",
                    "lifecycle-state": "ACTIVE",
                }
            ]
        else:
            domains = [
                domain
                for domain in domains
                if str(
                    domain.get("lifecycle-state")
                    or domain.get("lifecycle_state")
                    or "ACTIVE"
                ).upper()
                == "ACTIVE"
            ]

        context = CleanupContext(
            tenancy_id=self.args.tenancy_id,
            home_region=home_region,
            regions=regions,
            compartment_id=compartment_id,
            compartment=compartment,
            domains=domains,
            tagged_resources=tagged,
            managed_resources=managed,
        )
        return context


