#!/usr/bin/env python3
"""Responsibility: provide the cleanup command line and compatibility API.

Safety boundary: requires exact tenancy confirmation in execute mode; resource
validation and mutation remain in ``oci_cleanup`` modules.
Cleanup sequence role: parses arguments, constructs the cleanup engine, and
preserves the direct executable script path.

Imports from this module remain a compatibility surface for callers and tests.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from typing import Optional

from oci_cleanup import *  # noqa: F401,F403
from oci_cleanup import __all__ as package_api
from oci_cleanup.base import CleanupBase
from oci_cleanup.discovery import DiscoveryMixin
from oci_cleanup.domains.extras import ExtrasMixin
from oci_cleanup.engine import EngineMixin
from oci_cleanup.region import RegionMixin

__all__ = [*package_api, "QuickstartCleanup", "parse_args", "main"]


class QuickstartCleanup(
    EngineMixin,
    DiscoveryMixin,
    ExtrasMixin,
    RegionMixin,
    CleanupBase,
):
    """Discover unexpected resources in one OCI Quickstart installation."""


def _parse_bool(value: str) -> bool:
    normalized = value.lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise argparse.ArgumentTypeError("expected true or false")


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Discover and safely clean a Datadog OCI Quickstart installation "
            "when Terraform state is unavailable."
        )
    )
    parser.add_argument("--tenancy-id", required=True)
    parser.add_argument("--compartment-id")
    parser.add_argument("--domain-endpoint")
    parser.add_argument("--parent-stack-id")
    parser.add_argument("--profile")
    parser.add_argument("--oci-bin", default=os.getenv("OCI_BIN", "oci"))
    parser.add_argument(
        "--region-workers",
        type=int,
        default=1,
        help=(
            "Number of regions to clean concurrently (default: 1). "
            "Use a small value such as 4 to limit OCI throttling."
        ),
    )
    parser.add_argument(
        "--dry-run",
        type=_parse_bool,
        default=True,
        metavar="{true,false}",
        help="Report planned deletion when true; perform deletion when false (default: true).",
    )
    parser.add_argument(
        "--confirm-tenancy-id",
        help="Must exactly match --tenancy-id when --dry-run=false.",
    )
    parser.add_argument(
        "--delete-compartment",
        action="store_true",
        help=(
            "Separately opt in to deletion of a proven Quickstart-created, "
            "empty Datadog compartment."
        ),
    )
    args = parser.parse_args(argv)

    if args.region_workers < 1:
        parser.error("--region-workers must be at least 1")

    args.execute = not args.dry_run
    if not args.dry_run:
        if args.confirm_tenancy_id != args.tenancy_id:
            parser.error(
                "--confirm-tenancy-id must exactly match --tenancy-id when "
                "--dry-run=false"
            )
    return args


def main(argv: Optional[list[str]] = None) -> int:
    try:
        args = parse_args(argv)
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
        )
        cleanup = QuickstartCleanup(
            args=args,
            oci=OciCli(args.oci_bin, args.profile),
        )
        return cleanup.run()
    except (CleanupError, json.JSONDecodeError) as error:
        print(json.dumps({"status": "error", "error": str(error)}, indent=2))
        return 1


if __name__ == "__main__":
    sys.exit(main())
