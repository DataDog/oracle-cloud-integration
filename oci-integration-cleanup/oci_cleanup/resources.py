"""Responsibility: normalize OCI payloads and evaluate ownership evidence.

Safety boundary: only classifies resources and never mutates OCI state.
Cleanup sequence role: supports discovery and every service-specific ownership gate.

The accessors tolerate OCI's alternate field spellings and response envelopes.
Ownership helpers combine freeform and defined-tag evidence, while ``exact_owned``
also enforces expected name and compartment of the resource for destructive call sites.
"""

from __future__ import annotations

import datetime as dt
from typing import Any, Iterable, Optional

from .constants import OWNER_KEY, OWNER_VALUE, TAG_NAME, TAG_NAMESPACE_NAME

def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def resource_id(resource: dict[str, Any]) -> str:
    return str(
        resource.get("id")
        or resource.get("identifier")
        or resource.get("ocid")
        or ""
    )


def resource_name(resource: dict[str, Any]) -> str:
    return str(
        resource.get("display-name")
        or resource.get("display_name")
        or resource.get("secret-name")
        or resource.get("secret_name")
        or resource.get("name")
        or ""
    )


def resource_compartment(resource: dict[str, Any]) -> str:
    return str(
        resource.get("compartment-id")
        or resource.get("compartment_id")
        or ""
    )


def resource_type(resource: dict[str, Any]) -> str:
    return str(
        resource.get("resource-type")
        or resource.get("resource_type")
        or ""
    )


def lifecycle_state(resource: dict[str, Any]) -> str:
    return str(
        resource.get("lifecycle-state")
        or resource.get("lifecycle_state")
        or resource.get("state")
        or ""
    ).upper()


def is_deleted_or_deleting(resource: dict[str, Any]) -> bool:
    return lifecycle_state(resource) in {
        "DELETED",
        "DELETING",
        "DETACHED",
        "DETACHING",
        "TERMINATED",
        "TERMINATING",
    }


def data_items(payload: Any) -> list[dict[str, Any]]:
    if payload is None:
        return []
    data = payload.get("data", payload) if isinstance(payload, dict) else payload
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict):
        for key in ("items", "resources", "objects"):
            value = data.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
        return [data] if data else []
    return []


def freeform_tags(resource: dict[str, Any]) -> dict[str, str]:
    direct = (
        resource.get("freeform-tags")
        or resource.get("freeform_tags")
        or resource.get("freeformTags")
    )
    if isinstance(direct, dict):
        return {str(k): str(v) for k, v in direct.items()}

    # Identity Domains represent OCI tags under a SCIM extension as key/value
    # entries rather than the normal OCI map.
    for key, value in resource.items():
        normalized_key = "".join(
            character for character in key.lower() if character.isalnum()
        )
        if "ocitags" not in normalized_key or not isinstance(value, dict):
            continue
        entries = value.get("freeform-tags") or value.get("freeform_tags") or []
        if isinstance(entries, list):
            return {
                str(entry.get("key")): str(entry.get("value"))
                for entry in entries
                if isinstance(entry, dict) and entry.get("key") is not None
            }
    return {}


def defined_marker(resource: dict[str, Any]) -> bool:
    tags = (
        resource.get("defined-tags")
        or resource.get("defined_tags")
        or resource.get("definedTags")
        or {}
    )
    if not isinstance(tags, dict):
        return False
    namespace = tags.get(TAG_NAMESPACE_NAME, {})
    return isinstance(namespace, dict) and str(namespace.get(TAG_NAME)).lower() == "true"


def is_owned(resource: dict[str, Any]) -> bool:
    tags = freeform_tags(resource)
    return tags.get(OWNER_KEY, "").lower() == OWNER_VALUE


def exact_owned(
    resource: dict[str, Any],
    *,
    expected_names: Iterable[str],
    compartment_id: Optional[str] = None,
) -> bool:
    if not is_owned(resource) or resource_name(resource) not in set(expected_names):
        return False
    return not compartment_id or resource_compartment(resource) == compartment_id

