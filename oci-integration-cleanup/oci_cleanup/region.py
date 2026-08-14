"""Responsibility: coordinate and isolate per-region cleanup failures.

Safety boundary: preserves dependency order and records failures without unsafe IAM teardown.
Cleanup sequence role: dispatches stacks, services, network, and KMS for each region.

``cleanup_region`` defines the regional dependency chain from child stacks through
forwarding services and network to KMS. ``_cleanup_region_safely`` captures exceptions
per region so concurrent work completes while the engine retains a failure barrier.
"""

from __future__ import annotations

from .constants import LOGGER
from .models import CleanupContext


class RegionMixin:
    """Coordinate cleanup and failure isolation for each region."""

    def cleanup_region(self, context: CleanupContext, region: str) -> None:
        LOGGER.info("Stage 2/5: cleaning regional resources in %s", region)
        LOGGER.info("[%s] Checking Resource Manager child stacks", region)
        self.cleanup_regional_stacks(context, region)
        LOGGER.info("[%s] Checking connectors, event rules, and streams", region)
        self.cleanup_connectors_events_streams(context, region)
        LOGGER.info("[%s] Checking Object Storage buckets", region)
        self.cleanup_buckets(context, region)
        LOGGER.info("[%s] Checking forwarding functions", region)
        self.cleanup_functions(context, region)
        LOGGER.info("[%s] Checking Quickstart networking", region)
        self.cleanup_network(context, region)
        LOGGER.info("[%s] Checking KMS resources", region)
        self.cleanup_kms(context, region)


    def _cleanup_region_safely(
        self, context: CleanupContext, region: str
    ) -> None:
        try:
            self.cleanup_region(context, region)
        except Exception as error:
            message = f"Regional cleanup failed in {region}: {error}"
            self._record_failure(
                message,
                region=region,
                error=error,
            )
            LOGGER.error("%s", message)


