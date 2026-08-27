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

from .constants import AUTO_COMPARTMENT_NAME, FUNCTION_APP_NAME, LOGGER
from .errors import CleanupError
from .models import CleanupContext
from .resources import (
    data_items,
    exact_owned,
    is_deleted_or_deleting,
    is_owned,
    resource_compartment,
    resource_field,
    resource_id,
    resource_name,
    resource_type,
)


class DiscoveryMixin:
    """Discover and validate the cleanup context."""

    @staticmethod
    def _is_managed_function(
        context: CleanupContext, region: str, function_id: str
    ) -> bool:
        return any(
            resource.get("_region") == region
            and resource_compartment(resource) == context.compartment_id
            and resource_id(resource) == function_id
            and function_id.startswith("ocid1.fnfunc.")
            for resource in context.managed_resources
        )

    def _owned_function_applications(
        self, context: CleanupContext, region: str
    ) -> list[tuple[dict[str, Any], list[dict[str, Any]]]]:
        applications = self._list_region(
            region,
            [
                "fn",
                "application",
                "list",
                "--compartment-id",
                context.compartment_id,
            ],
        )
        discovered = []
        for application in applications:
            if not exact_owned(
                application,
                expected_names={FUNCTION_APP_NAME},
                compartment_id=context.compartment_id,
            ):
                continue
            functions = self._list_region(
                region,
                [
                    "fn",
                    "function",
                    "list",
                    "--application-id",
                    resource_id(application),
                ],
            )
            discovered.append(
                (
                    application,
                    [
                        function
                        for function in functions
                        if not is_deleted_or_deleting(function)
                    ],
                )
            )
        return discovered

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

    def _resolve_profile_domain(
        self,
        domains: list[dict[str, Any]],
    ) -> dict[str, Any]:
        explicit_domain_id = str(self.args.domain_id or "")
        if explicit_domain_id:
            matches = [
                domain
                for domain in domains
                if resource_id(domain) == explicit_domain_id
            ]
        else:
            matches = []
            for domain in domains:
                endpoint = str(
                    domain.get("url") or domain.get("endpoint") or ""
                )
                if not endpoint:
                    continue
                LOGGER.info(
                    "Checking OCI profile user in Identity Domain %s",
                    resource_name(domain) or resource_id(domain),
                )
                users = self.oci.list(
                    [
                        "identity-domains",
                        "users",
                        "list",
                        "--endpoint",
                        endpoint,
                        "--filter",
                        f'ocid eq "{self.args.profile_user_id}"',
                    ]
                )
                if any(
                    str(user.get("ocid") or "") == self.args.profile_user_id
                    for user in users
                ):
                    matches.append(domain)
        if len(matches) != 1:
            source = (
                f"explicit domain {explicit_domain_id}"
                if explicit_domain_id
                else f"OCI profile user {self.args.profile_user_id}"
            )
            raise CleanupError(
                f"Expected exactly one active Identity Domain for {source}, "
                f"found {[resource_id(domain) for domain in matches]}"
            )
        return matches[0]

    @staticmethod
    def _domain_regions(domain: dict[str, Any]) -> set[str]:
        regions = {
            str(resource_field(domain, "home-region", "") or "")
        }
        replicas = resource_field(domain, "replica-regions", [])
        if isinstance(replicas, list):
            regions.update(
                str(resource_field(replica, "region", "") or "")
                for replica in replicas
                if isinstance(replica, dict)
            )
        return {region for region in regions if region}

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
        profile_domain = self._resolve_profile_domain(domains)
        domain_regions = self._domain_regions(profile_domain)
        if not domain_regions:
            raise CleanupError(
                f"Identity Domain {resource_id(profile_domain)} reported no "
                "home or replica regions"
            )
        excluded_regions = sorted(set(regions) - domain_regions)
        regions = sorted(set(regions) & domain_regions)
        if not regions:
            raise CleanupError(
                "No tenancy subscriptions overlap the selected Identity "
                "Domain's home or replica regions"
            )
        LOGGER.info(
            "Using Identity Domain %s in %d region(s); excluding "
            "non-replicated region(s): %s",
            resource_name(profile_domain) or resource_id(profile_domain),
            len(regions),
            excluded_regions or "none",
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
                "Could not resolve the Datadog compartment. Supply --compartment-ocid."
            )
        else:
            raise CleanupError(
                f"Multiple candidate compartments found: "
                f"{sorted(compartment_candidates)}. Supply --compartment-ocid."
            )
        LOGGER.info("Resolved target compartment %s", compartment_id)

        matching_auto = [
            resource
            for resource in auto_compartments
            if resource_id(resource) == compartment_id
        ]
        compartment = matching_auto[0] if matching_auto else None

        context = CleanupContext(
            tenancy_id=self.args.tenancy_id,
            home_region=home_region,
            regions=regions,
            compartment_id=compartment_id,
            compartment=compartment,
            domains=[profile_domain],
            tagged_resources=tagged,
            managed_resources=managed,
        )
        return context


