"""Responsibility: coordinate the complete cleanup sequence for the assembled engine.

Safety boundary: withholds IAM and container teardown whenever regional or confirmation failures remain.
Cleanup sequence role: drives discovery, confirmations, regional work, IAM, tags, stacks, and compartment cleanup.

``EngineMixin.run`` is the stage orchestrator, including concurrent regional jobs
and the fail-closed transition to tenancy-wide teardown.
"""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor, as_completed

from .constants import LOGGER


class EngineMixin:
    """Coordinate the complete cleanup sequence for the assembled engine."""

    def _preserve(self, action_id: str, description: str) -> None:
        self.planned.append(
            {
                "id": action_id,
                "description": description,
                "status": "blocked",
            }
        )

    def run(self) -> int:
        LOGGER.info(
            "Starting Datadog OCI cleanup in %s mode",
            "execute" if self.execute else "dry-run",
        )
        LOGGER.warning(
            "This OCI-only cleanup does not unregister the tenancy from Datadog; "
            "disable or remove the integration separately to prevent recreation"
        )
        context = self.discover()
        self.prepare_extra_resource_cleanup(context)
        self.prepare_regional_stack_cleanup(context)

        worker_count = min(self.args.region_workers, len(context.regions))
        LOGGER.info(
            "Cleaning %d region(s) with %d worker(s)",
            len(context.regions),
            worker_count,
        )
        if worker_count == 1:
            for region in context.regions:
                self._cleanup_region_safely(context, region)
        else:
            with ThreadPoolExecutor(
                max_workers=worker_count,
                thread_name_prefix="oci-region",
            ) as executor:
                futures = {
                    executor.submit(
                        self._cleanup_region_safely,
                        context,
                        region,
                    ): region
                    for region in context.regions
                }
                for future in as_completed(futures):
                    future.result()

        if self.failures:
            # Keep IAM and credentials so failed child-stack destroy jobs can be
            # retried and declined extra resources remain usable. This is safer
            # than partially removing authorization.
            self._preserve(
                "home-identity",
                "Preserve IAM because cleanup has unresolved failures",
            )
        else:
            self.cleanup_home_identity(context)
            if not self.failures:
                self.cleanup_tags(context)

        if not self.failures:
            self.cleanup_parent_stack(context)
            self.delete_compartment(context)
        else:
            if self.args.parent_stack_id:
                self._preserve(
                    "parent-stack",
                    "Preserve parent stack because cleanup has failures",
                )
            if self.args.delete_compartment:
                self._preserve(
                    "compartment",
                    "Preserve compartment because cleanup has failures",
                )

        summary = {
            "mode": "execute" if self.execute else "dry-run",
            "tenancy_id": context.tenancy_id,
            "home_region": context.home_region,
            "regions": context.regions,
            "compartment_id": context.compartment_id,
            "actions": self.planned,
            "failures": self.failures,
        }
        print(json.dumps(summary, indent=2, sort_keys=True))
        LOGGER.info(
            "Cleanup finished with %d failure(s) and %d action(s)",
            len(self.failures),
            len(self.planned),
        )
        return 1 if self.failures else 0

