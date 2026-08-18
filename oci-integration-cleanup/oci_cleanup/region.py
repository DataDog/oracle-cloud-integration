"""Coordinate and isolate per-region cleanup failures."""

from __future__ import annotations

from .constants import LOGGER
from .models import CleanupContext


class RegionMixin:
    """Coordinate cleanup and failure isolation for each region."""

    def cleanup_region(self, context: CleanupContext, region: str) -> None:
        LOGGER.info("No regional cleanup domains enabled yet in %s", region)


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


