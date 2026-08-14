"""Assemble the cleanup engine and coordinate regional discovery."""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor, as_completed

from .constants import LOGGER
from .base import CleanupBase
from .discovery import DiscoveryMixin
from .region import RegionMixin


class EngineMixin:
    """Coordinate the complete cleanup sequence for the assembled engine."""

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

        summary = {
            "mode": "execute" if self.execute else "dry-run",
            "tenancy_id": context.tenancy_id,
            "home_region": context.home_region,
            "regions": context.regions,
            "compartment_id": context.compartment_id,
            "actions": self.planned,
            "failures": self.failures,
            "manifest": str(self.manifest.path) if self.execute else None,
        }
        print(json.dumps(summary, indent=2, sort_keys=True))
        if self.execute:
            self.manifest.data["last_summary"] = summary
            self.manifest.save()
        LOGGER.info(
            "Cleanup finished with %d failure(s) and %d action(s)",
            len(self.failures),
            len(self.planned),
        )
        return 1 if self.failures else 0

class QuickstartCleanup(
    EngineMixin,
    DiscoveryMixin,
    RegionMixin,
    CleanupBase,
):
    """Discover one Datadog OCI Quickstart installation."""

