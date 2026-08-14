"""Responsibility: parse command-line options and construct the cleanup engine.

Safety boundary: requires exact tenancy confirmation and a state file in execute mode.
Cleanup sequence role: provides the unchanged direct-script entry and exit behavior.

``parse_args`` defines dry-run, execution, compartment, profile, and concurrency
options; ``main`` validates their combinations, loads the manifest, wires ``OciCli``
to ``QuickstartCleanup``, and translates cleanup failures into process exit codes.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import pathlib
from typing import Optional

from .engine import QuickstartCleanup
from .errors import CleanupError
from .manifest import Manifest
from .oci import OciCli

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
        "--state-file",
        type=pathlib.Path,
        help="Execution manifest path (required for --execute)",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Perform deletion. Without this flag the script is read-only.",
    )
    parser.add_argument(
        "--confirm-tenancy-id",
        help="Must exactly match --tenancy-id in execute mode.",
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

    if args.execute:
        if args.confirm_tenancy_id != args.tenancy_id:
            parser.error(
                "--confirm-tenancy-id must exactly match --tenancy-id in execute mode"
            )
        if not args.state_file:
            parser.error("--state-file is required in execute mode")
    if not args.state_file:
        args.state_file = pathlib.Path(
            f"datadog-cleanup-{args.tenancy_id.rsplit('.', 1)[-1][:12]}.json"
        )
    return args


def main(argv: Optional[list[str]] = None) -> int:
    try:
        args = parse_args(argv)
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
        )
        manifest = Manifest.load(args.state_file, args.tenancy_id)
        cleanup = QuickstartCleanup(
            args=args,
            oci=OciCli(args.oci_bin, args.profile),
            manifest=manifest,
        )
        return cleanup.run()
    except (CleanupError, json.JSONDecodeError) as error:
        print(json.dumps({"status": "error", "error": str(error)}, indent=2))
        return 1
