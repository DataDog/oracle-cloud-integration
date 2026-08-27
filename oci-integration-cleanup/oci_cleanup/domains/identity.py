"""Responsibility: validate and remove Quickstart IAM domain and tenancy resources.

Safety boundary: requires exact names, tags, descriptions, matching rules, and policy references.
Cleanup sequence role: runs only after all regional cleanup succeeds.

``IdentityMixin`` resolves domain-scoped users and groups alongside tenancy-scoped
dynamic groups and policies, validates their cross-references, then removes them in
dependency order. Domain endpoints are passed explicitly to OCI identity commands.
"""

from __future__ import annotations

from typing import Any

from ..constants import (
    CONNECTOR_GROUP_DESCRIPTION,
    CONNECTOR_GROUP_NAME,
    DYNAMIC_POLICY_NAME,
    FUNCTION_GROUP_DESCRIPTION,
    FUNCTION_GROUP_NAME,
    GROUP_NAME,
    LOGGER,
    USER_NAME,
    USER_POLICY_NAME,
)
from ..models import CleanupContext
from ..resources import exact_owned, resource_id, resource_name


class IdentityMixin:
    """Validate and remove Quickstart IAM resources."""

    def _domain_endpoint(self, domain: dict[str, Any]) -> str:
        return str(domain.get("url") or domain.get("endpoint") or "")

    def _identity_resources(
        self,
        context: CleanupContext,
        kind: str,
        filter_expression: str,
    ) -> list[tuple[str, dict[str, Any]]]:
        found: list[tuple[str, dict[str, Any]]] = []
        for domain in context.domains:
            endpoint = self._domain_endpoint(domain)
            if not endpoint:
                continue
            LOGGER.info(
                "Checking %s in Identity Domain %s",
                kind,
                domain.get("display-name")
                or domain.get("display_name")
                or endpoint,
            )
            resources = self.oci.list(
                [
                    "identity-domains",
                    kind,
                    "list",
                    "--endpoint",
                    endpoint,
                    "--filter",
                    filter_expression,
                ]
            )
            found.extend((endpoint, resource) for resource in resources)
        return found

    def _validated_dynamic_groups(
        self,
        context: CleanupContext,
        policies: list[dict[str, Any]],
    ) -> list[tuple[str, dict[str, Any]]]:
        policy_candidate = next(
            (
                candidate
                for candidate in policies
                if resource_name(candidate) == DYNAMIC_POLICY_NAME
            ),
            None,
        )
        policy = next(
            (
                candidate
                for candidate in policies
                if exact_owned(
                    candidate,
                    expected_names={DYNAMIC_POLICY_NAME},
                    compartment_id=context.tenancy_id,
                )
            ),
            None,
        )
        statements = "\n".join(
            str(value) for value in (policy or {}).get("statements", [])
        )
        expected = {
            CONNECTOR_GROUP_NAME: (
                CONNECTOR_GROUP_DESCRIPTION,
                "serviceconnector",
            ),
            FUNCTION_GROUP_NAME: (FUNCTION_GROUP_DESCRIPTION, "fnfunc"),
        }
        validated: list[tuple[str, dict[str, Any]]] = []
        for endpoint, group in self._identity_resources(
            context,
            "dynamic-resource-groups",
            (
                f'displayName eq "{CONNECTOR_GROUP_NAME}" or '
                f'displayName eq "{FUNCTION_GROUP_NAME}"'
            ),
        ):
            name = resource_name(group)
            if name not in expected:
                continue
            description, resource_type = expected[name]
            matching_rule = str(
                group.get("matching-rule") or group.get("matching_rule") or ""
            )
            identifier = str(group.get("ocid") or resource_id(group))
            expected_rule = (
                f"All {{resource.type = '{resource_type}', "
                f"resource.compartment.id = '{context.compartment_id}'}}"
            )
            correct_rule = " ".join(matching_rule.split()) == " ".join(
                expected_rule.split()
            )
            if (
                str(group.get("description", "")) == description
                and correct_rule
                and identifier
                and (
                    identifier in statements
                    or policy_candidate is None
                )
            ):
                validated.append((endpoint, group))
            else:
                self._record_failure(
                    f"Dynamic group {name} failed ownership-chain validation; "
                    "manual review required",
                    resource_id=identifier,
                    region=context.home_region,
                )
        return validated

    def cleanup_home_identity(self, context: CleanupContext) -> None:
        LOGGER.info("Stage 3/5: cleaning home-region IAM and Identity Domains")
        policies_by_id: dict[str, dict[str, Any]] = {}
        for policy_name in (USER_POLICY_NAME, DYNAMIC_POLICY_NAME):
            for policy in self.oci.list(
                [
                    "--region",
                    context.home_region,
                    "iam",
                    "policy",
                    "list",
                    "--compartment-id",
                    context.tenancy_id,
                    "--name",
                    policy_name,
                ]
            ):
                identifier = resource_id(policy)
                if identifier:
                    policies_by_id[identifier] = policy
        policies = list(policies_by_id.values())
        failure_count = len(self.failures)
        validated_dynamic_groups = self._validated_dynamic_groups(context, policies)
        dynamic_groups_deleted = len(self.failures) == failure_count

        for endpoint, group in validated_dynamic_groups:
            identifier = resource_id(group)
            if not self.action(
                f"dynamic-group:{identifier}",
                f"Delete validated dynamic resource group {resource_name(group)}",
                command=[
                    "identity-domains",
                    "dynamic-resource-group",
                    "delete",
                    "--endpoint",
                    endpoint,
                    "--dynamic-resource-group-id",
                    identifier,
                    "--force-delete",
                    "true",
                    "--force",
                ],
            ):
                dynamic_groups_deleted = False

        for policy in policies:
            if not exact_owned(
                policy,
                expected_names={USER_POLICY_NAME, DYNAMIC_POLICY_NAME},
                compartment_id=context.tenancy_id,
            ):
                continue
            if (
                resource_name(policy) == DYNAMIC_POLICY_NAME
                and not dynamic_groups_deleted
            ):
                LOGGER.warning(
                    "Preserving %s because dynamic group cleanup was incomplete",
                    DYNAMIC_POLICY_NAME,
                )
                continue
            identifier = resource_id(policy)
            self.action(
                f"policy:{identifier}",
                f"Delete Datadog IAM policy {resource_name(policy)}",
                command=[
                    "--region",
                    context.home_region,
                    "iam",
                    "policy",
                    "delete",
                    "--policy-id",
                    identifier,
                    "--force",
                ],
            )

        users = [
            (endpoint, user)
            for endpoint, user in self._identity_resources(
                context,
                "users",
                f'userName eq "{USER_NAME}"',
            )
            if exact_owned(user, expected_names={USER_NAME})
        ]
        groups = [
            (endpoint, group)
            for endpoint, group in self._identity_resources(
                context,
                "groups",
                f'displayName eq "{GROUP_NAME}"',
            )
            if exact_owned(group, expected_names={GROUP_NAME})
        ]
        if len(users) > 1 or len(groups) > 1:
            ambiguous_ids = [
                resource_id(resource)
                for _, resource in [*users, *groups]
                if resource_id(resource)
            ]
            self._record_failure(
                "Multiple tagged dd-svc users or dd-svc-admin groups found; "
                "identity deletion requires manual review",
                resource_id=",".join(ambiguous_ids),
                region=context.home_region,
            )
            return

        if users:
            endpoint, user = users[0]
            scim_user_id = resource_id(user)
            api_keys = self.oci.list(
                [
                    "identity-domains",
                    "api-keys",
                    "list",
                    "--endpoint",
                    endpoint,
                    "--filter",
                    f'user.value eq "{scim_user_id}"',
                ]
            )
            for api_key in api_keys:
                identifier = resource_id(api_key)
                self.action(
                    f"api-key:{identifier}",
                    f"Delete API key {identifier} belonging to tagged {USER_NAME}",
                    command=[
                        "identity-domains",
                        "api-key",
                        "delete",
                        "--endpoint",
                        endpoint,
                        "--api-key-id",
                        identifier,
                        "--force",
                    ],
                )

        if groups:
            endpoint, group = groups[0]
            identifier = resource_id(group)
            self.action(
                f"identity-group:{identifier}",
                f"Delete tagged Identity Domain group {GROUP_NAME}",
                command=[
                    "identity-domains",
                    "group",
                    "delete",
                    "--endpoint",
                    endpoint,
                    "--group-id",
                    identifier,
                    "--force-delete",
                    "true",
                    "--force",
                ],
            )
        if users:
            endpoint, user = users[0]
            identifier = resource_id(user)
            self.action(
                f"identity-user:{identifier}",
                f"Delete tagged Identity Domain user {USER_NAME}",
                command=[
                    "identity-domains",
                    "user",
                    "delete",
                    "--endpoint",
                    endpoint,
                    "--user-id",
                    identifier,
                    "--force-delete",
                    "true",
                    "--force",
                ],
            )
