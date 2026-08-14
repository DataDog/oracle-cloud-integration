"""Responsibility: invoke the OCI CLI and normalize list responses.

Safety boundary: retries reads conservatively and only ignores explicit not-found responses.
Cleanup sequence role: provides the command boundary used by discovery and service cleanup.

``OciCli`` adds profile and JSON-output arguments consistently, executes subprocesses,
and raises ``CommandError`` with full command context. Its list path retries transient
failures and flattens OCI pagination payloads into resource dictionaries.
"""

from __future__ import annotations

import json
import subprocess
import time
from typing import Any, Optional

from .errors import CommandError
from .resources import data_items

class OciCli:
    def __init__(self, binary: str = "oci", profile: Optional[str] = None):
        self.binary = binary
        self.profile = profile

    def command(self, args: list[str]) -> list[str]:
        command = [self.binary, *args]
        if self.profile:
            command.extend(["--profile", self.profile])
        return command

    def run(
        self,
        args: list[str],
        *,
        attempts: int = 1,
        allow_not_found: bool = False,
    ) -> dict[str, Any]:
        command = self.command(args)
        last_error: Optional[CommandError] = None
        for attempt in range(1, attempts + 1):
            process = subprocess.run(
                command,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if process.returncode == 0:
                output = process.stdout.strip()
                return json.loads(output) if output else {}
            stderr = process.stderr.strip()
            stdout = process.stdout.strip()
            if allow_not_found and (
                "NotAuthorizedOrNotFound" in stderr
                or "404" in stderr
                or "does not exist" in stderr.lower()
                or " is DELETED" in stderr
            ):
                return {}
            last_error = CommandError(
                command,
                process.returncode,
                stderr,
                stdout,
            )
            if attempt < attempts:
                time.sleep(min(2**attempt, 5))
        assert last_error is not None
        raise last_error

    def list(self, args: list[str]) -> list[dict[str, Any]]:
        return data_items(self.run([*args, "--all"], attempts=2))
