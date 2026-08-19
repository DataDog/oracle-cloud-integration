"""Responsibility: define immutable Quickstart names, delays, and the cleanup logger.

Safety boundary: contains no OCI calls or mutable cleanup state.
Cleanup sequence role: supplies shared identifiers to discovery and deletion stages.

These values are the canonical Quickstart identity contract: expected IAM, tag,
stack, function, network, and KMS names plus OCI scheduling and retry intervals.
Changing one alters the evidence used to recognize resources as cleanup candidates.
"""

from __future__ import annotations

import datetime as dt
import logging

OWNER_KEY = "ownedby"
OWNER_VALUE = "datadog"
AUTO_COMPARTMENT_NAME = "Datadog"
AUTO_COMPARTMENT_DESCRIPTION = "Compartment for Datadog generated resources"
USER_NAME = "dd-svc"
GROUP_NAME = "dd-svc-admin"
USER_POLICY_NAME = "dd-svc-policy"
DYNAMIC_POLICY_NAME = "dd-dynamic-group-policy"
CONNECTOR_GROUP_NAME = "dd-dynamic-group-connectorhubs"
FUNCTION_GROUP_NAME = "dd-dynamic-group-functions"
CONNECTOR_GROUP_DESCRIPTION = (
    "[DO NOT REMOVE] Dynamic group for forwarding by service connector"
)
FUNCTION_GROUP_DESCRIPTION = "[DO NOT REMOVE] Dynamic group for forwarding functions"
TAG_NAMESPACE_NAME = "DatadogManaged"
TAG_NAME = "marker"
REGIONAL_STACK_PREFIX = "datadog-regional-stack-"
FUNCTION_APP_NAME = "dd-function-app"
FUNCTION_NAMES = {
    "dd-events-forwarder",
    "dd-logs-forwarder",
    "dd-metrics-forwarder",
}
BACKFILL_BUCKET_NAMES = {
    "dd-events-backfill",
    "dd-logs-backfill",
    "dd-metrics-backfill",
}
VCN_NAME = "dd-vcn"
SUBNET_NAME = "dd-vcn-private-subnet"
NAT_GATEWAY_NAME = "dd-vcn-natgateway"
SERVICE_GATEWAY_NAME = "dd-vcn-servicegateway"
VAULT_NAME = "datadog-vault"
KEY_NAME = "datadog-key"
SECRET_NAME = "DatadogAPIKey"
SECRET_DELETION_DELAY = dt.timedelta(days=1, minutes=5)
KMS_DELETION_DELAY = dt.timedelta(days=7, minutes=5)
SUBNET_VNIC_RETRY_SECONDS = 10 * 60
SUBNET_VNIC_RETRY_INTERVAL_SECONDS = 30
LOGGER = logging.getLogger("datadog-oci-cleanup")
