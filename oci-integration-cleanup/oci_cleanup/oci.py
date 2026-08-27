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

from .errors import CommandError, _oci_payload
from .resources import data_items


DEFAULT_COMMAND_TIMEOUT_SECONDS = 3 * 60


def _is_not_found(stderr: str, stdout: str) -> bool:
    payload = _oci_payload(stderr) or _oci_payload(stdout)
    code = str(payload.get("code") or "")
    status = int(payload.get("status") or 0)
    message = str(payload.get("message") or "").lower()
    return (
        code in {"NotAuthorizedOrNotFound", "NotFound"}
        or status == 404
        or "does not exist" in message
        or " is deleted" in message
    )


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
        timeout_seconds: Optional[float] = DEFAULT_COMMAND_TIMEOUT_SECONDS,
    ) -> dict[str, Any]:
        command = self.command(args)
        last_error: Optional[CommandError] = None
        for attempt in range(1, attempts + 1):
            try:
                process = subprocess.run(
                    command,
                    check=False,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=timeout_seconds,
                )
            except subprocess.TimeoutExpired as error:
                message = (
                    f"OCI CLI command timed out after {timeout_seconds:g} seconds"
                )
                output = str(error.stderr or error.stdout or "").strip()
                if output:
                    message = f"{message}: {output}"
                raise CommandError(command, 124, message) from error
            if process.returncode == 0:
                output = process.stdout.strip()
                if not output:
                    return {}
                try:
                    return json.loads(output)
                except json.JSONDecodeError as error:
                    last_error = CommandError(
                        command,
                        process.returncode,
                        (
                            "OCI CLI returned malformed JSON despite exit code 0: "
                            f"{error}: {output}"
                        ),
                    )
                    if attempt < attempts:
                        time.sleep(min(2**attempt, 5))
                        continue
                    raise last_error
            stderr = process.stderr.strip()
            stdout = process.stdout.strip()
            if allow_not_found and _is_not_found(stderr, stdout):
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

    def list(
        self,
        args: list[str],
        *,
        timeout_seconds: Optional[float] = DEFAULT_COMMAND_TIMEOUT_SECONDS,
    ) -> list[dict[str, Any]]:
        return data_items(
            self.run(
                [*args, "--all"],
                attempts=2,
                timeout_seconds=timeout_seconds,
            )
        )
