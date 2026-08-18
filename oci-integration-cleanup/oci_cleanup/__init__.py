"""Responsibility: publish the supported cleanup API.

Safety boundary: exposes validated primitives and the assembled engine without adding side effects.
Cleanup sequence role: serves imports for the compatibility facade and maintainers.

The exports collect constants, resource classifiers, context models, and the OCI
adapter so consumers need not depend on module layout.
"""

from __future__ import annotations

from .constants import (
    OWNER_KEY,
    OWNER_VALUE,
    AUTO_COMPARTMENT_NAME,
    AUTO_COMPARTMENT_DESCRIPTION,
    USER_NAME,
    GROUP_NAME,
    USER_POLICY_NAME,
    DYNAMIC_POLICY_NAME,
    CONNECTOR_GROUP_NAME,
    FUNCTION_GROUP_NAME,
    CONNECTOR_GROUP_DESCRIPTION,
    FUNCTION_GROUP_DESCRIPTION,
    TAG_NAMESPACE_NAME,
    TAG_NAME,
    REGIONAL_STACK_PREFIX,
    FUNCTION_APP_NAME,
    FUNCTION_NAMES,
    BACKFILL_BUCKET_NAMES,
    VCN_NAME,
    SUBNET_NAME,
    NAT_GATEWAY_NAME,
    SERVICE_GATEWAY_NAME,
    VAULT_NAME,
    KEY_NAME,
    SECRET_NAME,
    SECRET_DELETION_DELAY,
    KMS_DELETION_DELAY,
    SUBNET_VNIC_RETRY_SECONDS,
    SUBNET_VNIC_RETRY_INTERVAL_SECONDS,
    LOGGER,
)
from .errors import CleanupError, CommandError
from .resources import (
    utc_now,
    resource_id,
    resource_name,
    resource_compartment,
    lifecycle_state,
    is_deleted_or_deleting,
    data_items,
    freeform_tags,
    defined_marker,
    is_owned,
    exact_owned,
)
from .oci import OciCli
from .models import CleanupContext, ExtraResourceCandidate

__all__ = [
    "OWNER_KEY",
    "OWNER_VALUE",
    "AUTO_COMPARTMENT_NAME",
    "AUTO_COMPARTMENT_DESCRIPTION",
    "USER_NAME",
    "GROUP_NAME",
    "USER_POLICY_NAME",
    "DYNAMIC_POLICY_NAME",
    "CONNECTOR_GROUP_NAME",
    "FUNCTION_GROUP_NAME",
    "CONNECTOR_GROUP_DESCRIPTION",
    "FUNCTION_GROUP_DESCRIPTION",
    "TAG_NAMESPACE_NAME",
    "TAG_NAME",
    "REGIONAL_STACK_PREFIX",
    "FUNCTION_APP_NAME",
    "FUNCTION_NAMES",
    "BACKFILL_BUCKET_NAMES",
    "VCN_NAME",
    "SUBNET_NAME",
    "NAT_GATEWAY_NAME",
    "SERVICE_GATEWAY_NAME",
    "VAULT_NAME",
    "KEY_NAME",
    "SECRET_NAME",
    "SECRET_DELETION_DELAY",
    "KMS_DELETION_DELAY",
    "SUBNET_VNIC_RETRY_SECONDS",
    "SUBNET_VNIC_RETRY_INTERVAL_SECONDS",
    "LOGGER",
    "CleanupError",
    "CommandError",
    "utc_now",
    "resource_id",
    "resource_name",
    "resource_compartment",
    "lifecycle_state",
    "is_deleted_or_deleting",
    "data_items",
    "freeform_tags",
    "defined_marker",
    "is_owned",
    "exact_owned",
    "OciCli",
    "CleanupContext",
    "ExtraResourceCandidate",
]
