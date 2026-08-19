"""Responsibility: define cleanup and OCI command failure types.

Safety boundary: represents failures without performing recovery or deletion.
Cleanup sequence role: carries safety and execution failures to the facade and CLI.

``CleanupError`` marks failures that abort orchestration cleanly. ``CommandError``
adds the attempted OCI command, return code, and stderr so callers retain actionable
diagnostics without parsing subprocess exceptions.
"""

from __future__ import annotations

import json
from typing import Any


_SERVICE_NAMES = {
    "compute": "Compute",
    "events": "Events",
    "fn": "Functions",
    "iam": "IAM",
    "kms": "KMS",
    "network": "Networking",
    "ons": "Notifications",
    "os": "Object Storage",
    "resource-manager": "Resource Manager",
    "sch": "Service Connector Hub",
    "search": "Resource Search",
    "streaming": "Streaming",
    "vault": "Vault",
}


def _oci_payload(output: str) -> dict[str, Any]:
    start = output.find("{")
    if start < 0:
        return {}
    try:
        payload, _ = json.JSONDecoder().raw_decode(output[start:])
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _command_value(command: list[str], flag: str) -> str:
    try:
        return command[command.index(flag) + 1]
    except (ValueError, IndexError):
        return ""


def _service_name(command: list[str], payload: dict[str, Any]) -> str:
    for token in command:
        if token in _SERVICE_NAMES:
            return _SERVICE_NAMES[token]
    target = str(payload.get("target_service") or "").replace("_", " ").strip()
    return target.title() if target else "API"


def _customer_action(
    code: str,
    status: int,
    service: str,
    operation: str,
    message: str,
) -> str:
    normalized = f"{code} {service} {operation} {message}".lower()
    if " is deleted" in normalized:
        return "No action is required; the resource is already deleted."
    if code == "LimitExceeded" and "concurrently running jobs" in normalized:
        return (
            "Wait for existing Resource Manager jobs to finish, then rerun with "
            "--region-workers 1."
        )
    if status == 429 or code == "TooManyRequests":
        if service in {"KMS", "Vault"}:
            return (
                "Wait briefly, reduce --region-workers to 1, and rerun. If KMS "
                "cleanup still cannot complete and vault quota blocks reinstallation, "
                "manually schedule deletion of DatadogAPIKey, then datadog-key, then "
                "datadog-vault in this region. Vault quota is not released until the "
                "vault finishes deletion, which can take at least 7 days."
            )
        return (
            "OCI is throttling requests. Wait briefly, reduce --region-workers "
            "(preferably to 1), and rerun."
        )
    if "connection to endpoint timed out" in normalized:
        return (
            "Retry the cleanup. If timeouts continue, reduce --region-workers "
            "and verify regional OCI connectivity."
        )
    if "references the vnic" in normalized:
        return (
            "Remove or approve deletion of the attached VNIC and its owning "
            "resource, then rerun."
        )
    if "route table" in normalized and "subnet" in normalized:
        return (
            "Delete or detach the subnet dependency before retrying route-table "
            "cleanup."
        )
    if code in {"NotAuthorized", "NotAuthorizedOrNotFound"}:
        return (
            "Verify the OCI identity has permission to inspect and delete this "
            "resource, then rerun."
        )
    if "application cannot be deleted while it has associated functions" in normalized:
        return "Delete the remaining Functions resources, then rerun."
    if service in {"KMS", "Vault"}:
        return (
            "Retry cleanup. If vault quota blocks reinstallation, manually schedule "
            "deletion of DatadogAPIKey, then datadog-key, then datadog-vault in this "
            "region. Vault quota is released only after vault deletion completes, "
            "which can take at least 7 days."
        )
    if status >= 500:
        return (
            "This is an OCI service-side failure. Wait and rerun; use the request "
            "ID when contacting Oracle Support if it persists."
        )
    return "Review the OCI message and retry after correcting the reported condition."


class CleanupError(RuntimeError):
    """A safety or execution failure that should stop cleanup."""


class CommandError(CleanupError):
    """An OCI CLI command failed."""

    def __init__(
        self,
        command: list[str],
        returncode: int,
        stderr: str,
        stdout: str = "",
    ):
        self.command = command
        self.returncode = returncode
        self.stderr = stderr
        self.stdout = stdout
        safe_command = " ".join(command)
        self.raw_output = stderr.strip() or stdout.strip() or "no command output"
        self.payload = _oci_payload(self.raw_output)
        self.code = str(self.payload.get("code") or "CommandError")
        self.status = int(self.payload.get("status") or 0)
        self.operation = str(self.payload.get("operation_name") or "")
        self.service = _service_name(command, self.payload)
        self.region = _command_value(command, "--region")
        self.service_message = str(
            self.payload.get("message") or self.raw_output
        ).strip()
        self.request_id = str(self.payload.get("opc-request-id") or "")
        self.customer_action = _customer_action(
            self.code,
            self.status,
            self.service,
            self.operation,
            self.service_message,
        )
        operation = self.operation.replace("_", " ").strip()
        location = f" in {self.region}" if self.region else ""
        activity = f' during "{operation}"' if operation else ""
        status = f" (HTTP {self.status})" if self.status else ""
        summary = (
            f"OCI {self.service} service failed{activity}{location}: "
            f"{self.code}{status}: {self.service_message}"
        )
        summary += f" Customer action: {self.customer_action}"
        if self.request_id:
            summary += f" Request ID: {self.request_id}"
        self.summary = summary
        self.raw_message = (
            f"OCI command failed ({returncode}): {safe_command}: {self.raw_output}"
        )
        super().__init__(summary)


def raw_error_message(error: Exception) -> str:
    """Return complete diagnostics for persistence outside customer-facing output."""

    return str(getattr(error, "raw_message", str(error)))
