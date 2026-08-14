import argparse
import contextlib
import io
import json
import os
import pathlib
import sys
import tempfile
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import integration_cleanup as cleanup
import oci_cleanup
from oci_cleanup.resources import resource_field, resource_management_endpoint


TENANCY = "ocid1.tenancy.oc1..test"
COMPARTMENT = "ocid1.compartment.oc1..datadog"
HOME_REGION = "us-ashburn-1"


def parse_cleanup_args(argv, *, config: str = ""):
    with tempfile.TemporaryDirectory() as directory:
        config_path = pathlib.Path(directory) / "config"
        config_path.write_text(
            config or f"[DEFAULT]\ntenancy={TENANCY}\n",
            encoding="utf-8",
        )
        with patch.dict(
            os.environ,
            {
                "OCI_CLI_CONFIG_FILE": str(config_path),
                "OCI_CLI_PROFILE": "",
                "OCI_CLI_TENANCY": "",
            },
        ):
            return cleanup.parse_args(argv)


class FakeOci:
    def __init__(self):
        self.list_responses = {}
        self.run_responses = {}
        self.list_calls = []
        self.run_calls = []
        self.run_kwargs = []

    @staticmethod
    def _key(args):
        return " ".join(args)

    def add_list(self, contains, response):
        self.list_responses[contains] = response

    def add_run(self, contains, response):
        self.run_responses[contains] = response

    def list(self, args):
        key = self._key(args)
        self.list_calls.append(args)
        for contains, response in self.list_responses.items():
            if contains in key:
                if isinstance(response, Exception):
                    raise response
                return response() if callable(response) else response
        return []

    def run(self, args, **kwargs):
        key = self._key(args)
        self.run_calls.append(args)
        self.run_kwargs.append(kwargs)
        for contains, response in self.run_responses.items():
            if contains in key:
                if isinstance(response, Exception):
                    raise response
                return response() if callable(response) else response
        return {}


def owned(resource):
    return {**resource, "freeform-tags": {"ownedby": "datadog"}}


def context(**overrides):
    values = {
        "tenancy_id": TENANCY,
        "home_region": HOME_REGION,
        "regions": [HOME_REGION],
        "compartment_id": COMPARTMENT,
        "compartment": None,
        "domains": [],
        "tagged_resources": [],
    }
    values.update(overrides)
    return cleanup.CleanupContext(**values)


class TtyInput(io.StringIO):
    def isatty(self):
        return True


def extra_candidate(
    *,
    candidate_id="extra:function:us-ashburn-1:extra",
    kind="function",
    resource_id="extra",
    container_id="container",
    command=("delete", "extra"),
    requires_compute_confirmation=False,
):
    return cleanup.ExtraResourceCandidate(
        candidate_id=candidate_id,
        kind=kind,
        resource_id=resource_id,
        name=resource_id,
        region=HOME_REGION,
        container_id=container_id,
        container_name="Datadog container",
        impact="The parent cannot be deleted while this resource remains.",
        command=command,
        requires_compute_confirmation=requires_compute_confirmation,
    )


class CleanupTestCase(unittest.TestCase):
    def test_resource_management_endpoint_normalizes_oci_field_names(self):
        self.assertEqual(
            "https://hyphen.example",
            resource_management_endpoint(
                {"management-endpoint": "https://hyphen.example"}
            ),
        )
        self.assertEqual(
            "https://underscore.example",
            resource_management_endpoint(
                {"management_endpoint": "https://underscore.example"}
            ),
        )

    def test_facade_reexports_public_package_api(self):
        self.assertEqual(
            set(cleanup.__all__),
            {*oci_cleanup.__all__, "QuickstartCleanup", "parse_args", "main"},
        )
        for name in oci_cleanup.__all__:
            self.assertIs(getattr(oci_cleanup, name), getattr(cleanup, name))

    def make_cleaner(self, *, execute=False, oci=None, args=None):
        default_args = SimpleNamespace(
            execute=execute,
            tenancy_id=TENANCY,
            compartment_id=COMPARTMENT,
            delete_compartment=False,
            parent_stack_id=None,
            region_workers=1,
        )
        if args:
            for key, value in vars(args).items():
                setattr(default_args, key, value)
        return cleanup.QuickstartCleanup(
            args=default_args,
            oci=oci or FakeOci(),
        )

    def test_owned_tag_supports_normal_and_identity_domain_shapes(self):
        self.assertTrue(cleanup.is_owned(owned({"id": "normal"})))
        identity = {
            "urn:ietf:params:scim:schemas:oracle:idcs:extension:ociTags": {
                "freeform-tags": [{"key": "ownedby", "value": "datadog"}]
            }
        }
        self.assertTrue(cleanup.is_owned(identity))
        normalized_identity = {
            "urnietfparamsscimschemasoracleidcsextension_oci_tags": {
                "freeform_tags": [{"key": "ownedby", "value": "datadog"}]
            }
        }
        self.assertTrue(cleanup.is_owned(normalized_identity))
        self.assertFalse(cleanup.is_owned({"freeform-tags": {"ownedby": "customer"}}))

    def test_exact_owned_rejects_wrong_name_compartment_and_tag(self):
        resource = owned(
            {
                "id": "app",
                "display-name": cleanup.FUNCTION_APP_NAME,
                "compartment-id": COMPARTMENT,
            }
        )
        self.assertTrue(
            cleanup.exact_owned(
                resource,
                expected_names={cleanup.FUNCTION_APP_NAME},
                compartment_id=COMPARTMENT,
            )
        )
        self.assertFalse(
            cleanup.exact_owned(
                resource,
                expected_names={"other"},
                compartment_id=COMPARTMENT,
            )
        )
        self.assertFalse(
            cleanup.exact_owned(
                resource,
                expected_names={cleanup.FUNCTION_APP_NAME},
                compartment_id="customer-compartment",
            )
        )

    def test_resource_field_supports_hyphenated_and_normalized_names(self):
        self.assertEqual(
            "hyphenated",
            resource_field({"subnet-id": "hyphenated"}, "subnet-id"),
        )
        self.assertEqual(
            "normalized",
            resource_field({"subnet_id": "normalized"}, "subnet-id"),
        )
        self.assertFalse(
            resource_field({"is_primary": False}, "is-primary", True)
        )

    def test_execute_requires_exact_confirmation(self):
        common = ["--dry-run", "false"]
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                parse_cleanup_args(common)
            with self.assertRaises(SystemExit):
                parse_cleanup_args(
                    [*common, "--confirm-tenancy-id", "wrong-tenancy"]
                )
        args = parse_cleanup_args(
            [
                *common,
                "--confirm-tenancy-id",
                TENANCY,
            ]
        )
        self.assertTrue(args.execute)
        self.assertFalse(args.dry_run)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                parse_cleanup_args(
                    [
                        *common,
                        "--confirm-tenancy-id",
                        TENANCY,
                        "--state-file",
                        "removed.json",
                    ]
                )

    def test_dry_run_uses_default_profile_tenancy(self):
        args = parse_cleanup_args([])
        self.assertFalse(args.execute)
        self.assertTrue(args.dry_run)
        self.assertEqual(TENANCY, args.tenancy_id)
        self.assertEqual(1, args.region_workers)

    def test_dry_run_accepts_explicit_true_and_rejects_other_values(self):
        args = parse_cleanup_args(["--dry-run", "true"])
        self.assertTrue(args.dry_run)
        self.assertFalse(args.execute)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                parse_cleanup_args(["--dry-run", "yes"])

    def test_named_profile_supplies_tenancy(self):
        args = parse_cleanup_args(
            ["--profile", "CUSTOMER"],
            config=f"[CUSTOMER]\ntenancy={TENANCY}\n",
        )
        self.assertEqual(TENANCY, args.tenancy_id)

    def test_compartment_ocid_sets_internal_compartment_id(self):
        args = parse_cleanup_args(["--compartment-ocid", COMPARTMENT])
        self.assertEqual(COMPARTMENT, args.compartment_id)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                parse_cleanup_args(["--compartment-id", COMPARTMENT])

    def test_missing_profile_tenancy_is_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                parse_cleanup_args([], config="[DEFAULT]\nregion=us-ashburn-1\n")

    def test_region_workers_must_be_positive(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                parse_cleanup_args(
                    ["--region-workers", "0"]
                )
        args = parse_cleanup_args(["--region-workers", "4"])
        self.assertEqual(4, args.region_workers)

    def test_oci_binary_is_resolved_and_missing_binary_is_reported(self):
        with patch.object(cleanup.shutil, "which", return_value="/opt/bin/oci"):
            self.assertEqual("/opt/bin/oci", cleanup._resolve_oci_binary("oci"))

        with patch.object(cleanup.shutil, "which", return_value=None):
            with self.assertRaises(cleanup.CleanupError) as raised:
                cleanup._resolve_oci_binary("missing-oci")
        self.assertIn("--oci-bin/OCI_BIN", str(raised.exception))

    def test_dry_run_action_never_invokes_mutation(self):
        cleaner = self.make_cleaner()
        invoked = []
        result = cleaner.action(
            "delete:test",
            "Delete test",
            function=lambda: invoked.append(True),
        )
        self.assertTrue(result)
        self.assertEqual([], invoked)
        self.assertEqual("planned", cleaner.planned[0]["status"])

    def test_oci_command_error_includes_stdout_when_stderr_is_empty(self):
        process = SimpleNamespace(
            returncode=2,
            stdout="Invalid value for --wait-for-state: TERMINATED",
            stderr="",
        )
        with patch("oci_cleanup.oci.subprocess.run", return_value=process):
            with self.assertRaises(cleanup.CommandError) as raised:
                cleanup.OciCli().run(["compute", "instance", "terminate"])

        self.assertIn("Invalid value", str(raised.exception))
        self.assertEqual(process.stdout, raised.exception.stdout)

    def test_extra_resource_dry_run_reports_without_prompting(self):
        cleaner = self.make_cleaner()
        cleaner.discover_extra_resources = lambda _context: [extra_candidate()]
        cleaner._ask_yes_no = lambda _prompt: self.fail("dry-run prompted")

        cleaner.prepare_extra_resource_cleanup(context())

        self.assertEqual("confirmation-required", cleaner.planned[0]["status"])
        self.assertEqual(set(), cleaner.approved_extra_ids)
        self.assertEqual([], cleaner.failures)

    def test_extra_resource_prompt_accepts_only_y_or_n(self):
        cleaner = self.make_cleaner(execute=True)
        cleaner.discover_extra_resources = lambda _context: [extra_candidate()]

        with patch("oci_cleanup.domains.extras.sys.stdin", TtyInput("maybe\ny\n")):
            with contextlib.redirect_stderr(io.StringIO()) as stderr:
                cleaner.prepare_extra_resource_cleanup(context())

        self.assertIn("Please answer y or n.", stderr.getvalue())
        self.assertEqual(
            {"extra:function:us-ashburn-1:extra"},
            cleaner.approved_extra_ids,
        )
        self.assertEqual("approved", cleaner.planned[0]["status"])

    def test_extra_resource_non_tty_fails_closed(self):
        cleaner = self.make_cleaner(execute=True)
        cleaner.discover_extra_resources = lambda _context: [extra_candidate()]

        with patch("oci_cleanup.domains.extras.sys.stdin", io.StringIO("y\n")):
            cleaner.prepare_extra_resource_cleanup(context())

        self.assertEqual(set(), cleaner.approved_extra_ids)
        self.assertEqual("declined", cleaner.planned[0]["status"])
        self.assertTrue(
            any("not approved" in failure["message"] for failure in cleaner.failures)
        )

    def test_extra_resource_approval_is_session_local(self):
        first = self.make_cleaner(execute=True)
        first.discover_extra_resources = lambda _context: [extra_candidate()]
        with patch("oci_cleanup.domains.extras.sys.stdin", TtyInput("y\n")):
            first.prepare_extra_resource_cleanup(context())

        resumed = self.make_cleaner(execute=True)
        resumed.discover_extra_resources = lambda _context: [extra_candidate()]
        prompts = []
        resumed._ask_yes_no = lambda prompt: prompts.append(prompt) or False
        resumed.prepare_extra_resource_cleanup(context())

        self.assertEqual(1, len(prompts))
        self.assertEqual(set(), resumed.approved_extra_ids)
        self.assertEqual("declined", resumed.planned[0]["status"])

    def test_unsupported_extra_reports_manual_remediation_without_prompt(self):
        cleaner = self.make_cleaner(execute=True)
        candidate = extra_candidate(
            candidate_id="extra:unsupported-vnic:us-ashburn-1:vnic",
            kind="unsupported-vnic",
            resource_id="vnic",
            command=None,
        )
        cleaner.discover_extra_resources = lambda _context: [candidate]
        cleaner._ask_yes_no = lambda _prompt: self.fail(
            "unsupported resource prompted for unsafe deletion"
        )

        cleaner.prepare_extra_resource_cleanup(context())

        self.assertEqual("unsupported", cleaner.planned[0]["status"])
        self.assertTrue(
            any(
                "cannot be safely deleted" in failure["message"]
                for failure in cleaner.failures
            )
        )

    def test_primary_vnic_requires_second_compute_confirmation(self):
        candidate = extra_candidate(
            candidate_id="extra:compute-instance:us-ashburn-1:instance",
            kind="compute-instance",
            resource_id="instance",
            command=("compute", "instance", "terminate"),
            requires_compute_confirmation=True,
        )
        declined = self.make_cleaner(execute=True)
        declined.discover_extra_resources = lambda _context: [candidate]
        with patch("oci_cleanup.domains.extras.sys.stdin", TtyInput("y\nn\n")):
            with contextlib.redirect_stderr(io.StringIO()):
                declined.prepare_extra_resource_cleanup(context())
        self.assertEqual("declined", declined.planned[0]["status"])

        approved = self.make_cleaner(execute=True)
        approved.discover_extra_resources = lambda _context: [candidate]
        with patch("oci_cleanup.domains.extras.sys.stdin", TtyInput("y\ny\n")):
            with contextlib.redirect_stderr(io.StringIO()):
                approved.prepare_extra_resource_cleanup(context())
        self.assertEqual("approved", approved.planned[0]["status"])

    def test_approved_network_extras_delete_in_dependency_order(self):
        cleaner = self.make_cleaner(execute=True)
        candidates = [
            extra_candidate(
                candidate_id=f"extra:{kind}:{HOME_REGION}:{kind}",
                kind=kind,
                resource_id=kind,
                command=("delete", kind),
            )
            for kind in [
                "service-gateway",
                "route-table",
                "subnet",
                "secondary-vnic",
            ]
        ]
        cleaner.extra_candidates = candidates
        cleaner.approved_extra_ids = {
            candidate.candidate_id for candidate in candidates
        }

        cleaner._delete_approved_extras(
            region=HOME_REGION,
            kinds={candidate.kind for candidate in candidates},
        )

        self.assertEqual(
            [
                "delete secondary-vnic",
                "delete subnet",
                "delete route-table",
                "delete service-gateway",
            ],
            [" ".join(command) for command in cleaner.oci.run_calls],
        )
    def test_oci_success_with_malformed_json_raises_command_error(self):
        process = SimpleNamespace(
            returncode=0,
            stdout="not-json",
            stderr="",
        )
        with patch("oci_cleanup.oci.subprocess.run", return_value=process):
            with self.assertRaises(cleanup.CommandError) as raised:
                cleanup.OciCli().run(["search", "resource", "structured-search"])

        self.assertIn("malformed JSON", str(raised.exception))

    def test_oci_not_found_requires_structured_error_evidence(self):
        unrelated = SimpleNamespace(
            returncode=1,
            stdout="",
            stderr=json.dumps(
                {
                    "code": "InternalError",
                    "status": 500,
                    "message": "Request identifier contains 404 but is not missing",
                }
            ),
        )
        with patch("oci_cleanup.oci.subprocess.run", return_value=unrelated):
            with self.assertRaises(cleanup.CommandError):
                cleanup.OciCli().run(["fn", "function", "delete"], allow_not_found=True)

        missing = SimpleNamespace(
            returncode=1,
            stdout="",
            stderr=json.dumps(
                {
                    "code": "NotFound",
                    "status": 404,
                    "message": "Resource was not found",
                }
            ),
        )
        with patch("oci_cleanup.oci.subprocess.run", return_value=missing):
            self.assertEqual(
                {},
                cleanup.OciCli().run(
                    ["fn", "function", "delete"],
                    allow_not_found=True,
                ),
            )

    def test_discovery_uses_common_tagged_resource_compartment(self):
        oci = FakeOci()
        oci.add_list(
            "iam region-subscription list",
            [
                {
                    "region-name": HOME_REGION,
                    "is-home-region": True,
                    "status": "READY",
                }
            ],
        )
        oci.add_list("iam domain list", [])
        oci.add_run(
            "freeformTags.key = 'ownedby'",
            {
                "data": {
                    "items": [
                        owned(
                            {
                                "identifier": "app",
                                "display-name": cleanup.FUNCTION_APP_NAME,
                                "resource-type": "FnApplication",
                                "compartment-id": COMPARTMENT,
                            }
                        )
                    ]
                }
            },
        )
        cleaner = self.make_cleaner(
            oci=oci, args=argparse.Namespace(compartment_id=None)
        )
        discovered = cleaner.discover()
        self.assertEqual(COMPARTMENT, discovered.compartment_id)

    def test_discovery_accepts_explicit_compartment_without_tag_evidence(self):
        oci = FakeOci()
        oci.add_list(
            "iam region-subscription list",
            [
                {
                    "region-name": HOME_REGION,
                    "is-home-region": True,
                    "status": "READY",
                }
            ],
        )
        oci.add_list("iam domain list", [])
        cleaner = self.make_cleaner(oci=oci)

        discovered = cleaner.discover()

        self.assertEqual(COMPARTMENT, discovered.compartment_id)

    def test_discovery_aborts_on_ambiguous_tagged_compartments(self):
        oci = FakeOci()
        oci.add_list(
            "iam region-subscription list",
            [
                {
                    "region-name": HOME_REGION,
                    "is-home-region": True,
                    "status": "READY",
                }
            ],
        )
        oci.add_list("iam domain list", [])
        oci.add_run(
            "freeformTags.key = 'ownedby'",
            {
                "data": {
                    "items": [
                        owned(
                            {
                                "identifier": "app-a",
                                "display-name": cleanup.FUNCTION_APP_NAME,
                                "resource-type": "FnApplication",
                                "compartment-id": "compartment-a",
                            }
                        ),
                        owned(
                            {
                                "identifier": "app-b",
                                "display-name": cleanup.FUNCTION_APP_NAME,
                                "resource-type": "FnApplication",
                                "compartment-id": "compartment-b",
                            }
                        ),
                    ]
                }
            },
        )
        cleaner = self.make_cleaner(
            oci=oci, args=argparse.Namespace(compartment_id=None)
        )
        with self.assertRaises(cleanup.CleanupError):
            cleaner.discover()

    def test_execute_action_always_attempts_function(self):
        cleaner = self.make_cleaner(execute=True)
        invoked = []

        for _ in range(2):
            result = cleaner.action(
                "delete:test",
                "Delete test",
                function=lambda: invoked.append(True),
            )
            self.assertTrue(result)

        self.assertEqual([True, True], invoked)
        self.assertEqual(["completed", "completed"], [
            action["status"] for action in cleaner.planned
        ])

    def test_execute_action_commands_allow_missing_resources(self):
        cleaner = self.make_cleaner(execute=True)

        self.assertTrue(
            cleaner.action(
                "delete:test",
                "Delete test",
                command=["fn", "function", "delete"],
            )
        )

        self.assertEqual(
            {"attempts": 3, "allow_not_found": True},
            cleaner.oci.run_kwargs[0],
        )

    def test_failed_deletion_records_structured_oci_details(self):
        cleaner = self.make_cleaner(execute=True)
        error = cleanup.CommandError(
            ["oci", "--region", HOME_REGION, "fn", "function", "delete"],
            1,
            json.dumps(
                {
                    "code": "Conflict",
                    "status": 409,
                    "message": "Function still has a dependency",
                }
            ),
        )
        cleaner.oci.add_run("fn function delete", error)

        result = cleaner.action(
            "delete:function",
            "Delete function",
            command=["fn", "function", "delete"],
            details={"resource_id": "ocid1.fnfunc.oc1..test", "region": HOME_REGION},
        )

        self.assertFalse(result)
        expected = {
            "resource_id": "ocid1.fnfunc.oc1..test",
            "region": HOME_REGION,
            "error_code": "Conflict",
            "deletion_message": "Function still has a dependency",
        }
        for key, value in expected.items():
            self.assertEqual(value, cleaner.failures[0][key])
            self.assertEqual(value, cleaner.planned[0][key])

    def test_functions_cleanup_preserves_customer_application(self):
        oci = FakeOci()
        oci.add_list(
            "fn application list",
            [
                owned(
                    {
                        "id": "dd-app",
                        "display-name": cleanup.FUNCTION_APP_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                ),
                {
                    "id": "customer-app",
                    "display-name": cleanup.FUNCTION_APP_NAME,
                    "compartment-id": COMPARTMENT,
                },
            ],
        )
        oci.add_list(
            "fn function list",
            [
                owned(
                    {
                        "id": "logs",
                        "display-name": "dd-logs-forwarder",
                    }
                ),
                {
                    "id": "events",
                    "display-name": "dd-events-forwarder",
                    "defined-tags": {
                        "DatadogManaged": {"marker": "true"}
                    },
                },
                {
                    "id": "events-suffixed",
                    "display-name": "dd-events-forwarder-309",
                    "defined-tags": {
                        "DatadogManaged": {"marker": "true"}
                    },
                },
                {
                    "id": "ocid1.fnfunc.oc1..search-owned",
                    "display-name": "dd-metrics-forwarder",
                },
                {"id": "untagged-metrics", "display-name": "dd-metrics-forwarder"},
                {
                    "id": "deleting-logs",
                    "display-name": "dd-logs-forwarder",
                    "lifecycle-state": "DELETING",
                },
            ],
        )
        cleaner = self.make_cleaner(oci=oci)
        cleaner.cleanup_functions(
            context(
                tagged_resources=[
                    {
                        "identifier": "ocid1.fnfunc.oc1..search-owned",
                        "display-name": "dd-metrics-forwarder",
                        "compartment-id": COMPARTMENT,
                        "_region": HOME_REGION,
                    }
                ],
                managed_resources=[
                    {
                        "identifier": "events",
                        "display-name": "dd-events-forwarder",
                        "compartment-id": COMPARTMENT,
                        "defined-tags": {
                            "DatadogManaged": {"marker": "true"}
                        },
                        "_region": HOME_REGION,
                    },
                    {
                        "identifier": "events-suffixed",
                        "display-name": "dd-events-forwarder-309",
                        "compartment-id": COMPARTMENT,
                        "defined-tags": {
                            "DatadogManaged": {"marker": "true"}
                        },
                        "_region": HOME_REGION,
                    }
                ]
            ),
            HOME_REGION,
        )
        action_ids = {action["id"] for action in cleaner.planned}
        self.assertIn(f"function:{HOME_REGION}:logs", action_ids)
        self.assertIn(f"function:{HOME_REGION}:events", action_ids)
        self.assertIn(f"function:{HOME_REGION}:events-suffixed", action_ids)
        self.assertIn(
            f"function:{HOME_REGION}:ocid1.fnfunc.oc1..search-owned",
            action_ids,
        )
        self.assertIn(
            f"function:{HOME_REGION}:untagged-metrics",
            action_ids,
        )
        self.assertNotIn(f"function:{HOME_REGION}:deleting-logs", action_ids)
        self.assertIn(f"function-app:{HOME_REGION}:dd-app", action_ids)
        self.assertFalse(any("customer-app" in action_id for action_id in action_ids))

    def test_discovers_unknown_function_inside_owned_application(self):
        oci = FakeOci()
        oci.add_list(
            "fn application list",
            [
                owned(
                    {
                        "id": "dd-app",
                        "display-name": cleanup.FUNCTION_APP_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        oci.add_list(
            "fn function list",
            [
                {"id": "known", "display-name": "dd-logs-forwarder"},
                {"id": "extra", "display-name": "customer-function"},
                {
                    "id": "deleting-extra",
                    "display-name": "customer-function",
                    "lifecycle-state": "DELETING",
                },
            ],
        )

        candidates = self.make_cleaner(oci=oci)._discover_function_extras(
            context(), HOME_REGION
        )

        self.assertEqual(["extra"], [candidate.resource_id for candidate in candidates])
        self.assertIn("fn function delete", " ".join(candidates[0].command or ()))

    def test_declined_extra_function_blocks_application_deletion(self):
        oci = FakeOci()
        oci.add_list(
            "fn application list",
            [
                owned(
                    {
                        "id": "dd-app",
                        "display-name": cleanup.FUNCTION_APP_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        oci.add_list("fn function list", [])
        cleaner = self.make_cleaner(oci=oci)
        cleaner.extra_candidates = [
            extra_candidate(container_id="dd-app")
        ]

        cleaner.cleanup_functions(context(), HOME_REGION)

        application = next(
            action
            for action in cleaner.planned
            if action["id"] == f"function-app:{HOME_REGION}:dd-app"
        )
        self.assertEqual("blocked", application["status"])

    def test_discovers_secondary_and_primary_compute_vnic_actions(self):
        oci = FakeOci()
        oci.add_run(
            "query Vnic resources",
            {
                "data": {
                    "items": [
                        {"identifier": "primary-vnic"},
                        {"identifier": "secondary-vnic"},
                    ]
                }
            },
        )
        vnics = iter(
            [
                {
                    "data": {
                        "id": "primary-vnic",
                        "display-name": "primary",
                        "subnet-id": "subnet",
                        "compartment-id": "instance-compartment",
                        "is-primary": True,
                    }
                },
                {
                    "data": {
                        "id": "secondary-vnic",
                        "display-name": "secondary",
                        "subnet-id": "subnet",
                        "compartment-id": "instance-compartment",
                        "is-primary": False,
                    }
                },
            ]
        )
        oci.add_run("network vnic get", lambda: next(vnics))
        attachments = iter(
            [
                [{"id": "primary-attachment", "instance-id": "instance-a"}],
                [{"id": "secondary-attachment", "instance-id": "instance-b"}],
            ]
        )
        oci.add_list("compute vnic-attachment list", lambda: next(attachments))
        instances = iter(
            [
                {"data": {"id": "instance-a", "display-name": "primary-instance"}},
                {"data": {"id": "instance-b", "display-name": "secondary-instance"}},
            ]
        )
        oci.add_run("compute instance get", lambda: next(instances))
        subnet = {
            "id": "subnet",
            "display-name": cleanup.SUBNET_NAME,
            "compartment-id": COMPARTMENT,
        }

        candidates = self.make_cleaner(oci=oci)._discover_vnic_extras(
            context(), HOME_REGION, subnet
        )
        by_kind = {candidate.kind: candidate for candidate in candidates}

        self.assertIn("compute-instance", by_kind)
        self.assertIn("secondary-vnic", by_kind)
        self.assertTrue(by_kind["compute-instance"].requires_compute_confirmation)
        self.assertIn(
            "--preserve-boot-volume",
            by_kind["compute-instance"].command or (),
        )
        compute_command = by_kind["compute-instance"].command or ()
        wait_state_index = compute_command.index("--wait-for-state") + 1
        self.assertEqual("SUCCEEDED", compute_command[wait_state_index])
        self.assertIn("detach-vnic", by_kind["secondary-vnic"].command or ())

    def test_unidentified_vnic_becomes_confirmable_detach_candidate(self):
        oci = FakeOci()
        oci.add_run(
            "query Vnic resources",
            {"data": {"items": [{"identifier": "unidentified-vnic"}]}},
        )
        oci.add_run(
            "network vnic get",
            {
                "data": {
                    "id": "unidentified-vnic",
                    "display-name": "untagged-vnic",
                    "subnet-id": "subnet",
                    "compartment-id": "instance-compartment",
                    "is-primary": False,
                }
            },
        )
        oci.add_list("compute vnic-attachment list", [])
        subnet = {
            "id": "subnet",
            "display-name": cleanup.SUBNET_NAME,
            "compartment-id": COMPARTMENT,
        }

        candidates = self.make_cleaner(oci=oci)._discover_vnic_extras(
            context(), HOME_REGION, subnet
        )

        self.assertEqual(1, len(candidates))
        candidate = candidates[0]
        self.assertEqual("unverified-secondary-vnic", candidate.kind)
        self.assertIn("detach-vnic", candidate.command or ())
        self.assertIn("instance-compartment", candidate.command or ())

    def test_discovers_primary_vnic_attachment_in_another_compartment(self):
        oci = FakeOci()
        oci.add_run(
            "query Vnic resources",
            {"data": {"items": [{"identifier": "cross-compartment-vnic"}]}},
        )
        oci.add_run(
            "network vnic get",
            {
                "data": {
                    "id": "cross-compartment-vnic",
                    "display-name": "cross-compartment-instance",
                    "subnet-id": "subnet",
                    "compartment-id": COMPARTMENT,
                    "is-primary": True,
                }
            },
        )
        oci.add_list(
            "iam compartment list",
            [
                {
                    "id": "instance-compartment",
                    "lifecycle-state": "ACTIVE",
                }
            ],
        )
        attachment_responses = iter(
            [
                [],
                [
                    {
                        "id": "attachment",
                        "instance-id": "cross-compartment-instance",
                        "lifecycle-state": "ATTACHED",
                    }
                ],
            ]
        )
        oci.add_list(
            "compute vnic-attachment list",
            lambda: next(attachment_responses),
        )
        oci.add_run(
            "compute instance get",
            {
                "data": {
                    "id": "cross-compartment-instance",
                    "display-name": "instance",
                    "compartment-id": "instance-compartment",
                }
            },
        )
        subnet = {
            "id": "subnet",
            "display-name": cleanup.SUBNET_NAME,
            "compartment-id": COMPARTMENT,
        }

        candidates = self.make_cleaner(oci=oci)._discover_vnic_extras(
            context(), HOME_REGION, subnet
        )

        self.assertEqual(1, len(candidates))
        candidate = candidates[0]
        self.assertEqual("compute-instance", candidate.kind)
        self.assertTrue(candidate.requires_compute_confirmation)
        self.assertIn("terminate", candidate.command or ())

    def test_bucket_cleanup_deletes_only_proven_backfill_buckets(self):
        oci = FakeOci()
        oci.add_run("os ns get", {"data": "test-namespace"})
        oci.add_list(
            "os bucket list",
            [
                {
                    "name": "dd-events-backfill",
                    "defined-tags": {
                        "DatadogManaged": {"marker": "true"}
                    },
                },
                owned({"name": "dd-logs-backfill"}),
                owned({"name": "dd-customer-data"}),
                {"name": "dd-metrics-backfill"},
            ],
        )
        cleaner = self.make_cleaner(oci=oci)
        cleaner.cleanup_buckets(context(), HOME_REGION)

        action_ids = {action["id"] for action in cleaner.planned}
        self.assertIn(
            f"bucket:{HOME_REGION}:dd-events-backfill",
            action_ids,
        )
        self.assertIn(
            f"bucket:{HOME_REGION}:dd-logs-backfill",
            action_ids,
        )
        self.assertNotIn(
            f"bucket:{HOME_REGION}:dd-customer-data",
            action_ids,
        )
        self.assertNotIn(
            f"bucket:{HOME_REGION}:dd-metrics-backfill",
            action_ids,
        )

    def test_bucket_cleanup_reconciles_marker_proven_bucket_outside_compartment(self):
        oci = FakeOci()
        oci.add_run("os ns get", {"data": "test-namespace"})
        oci.add_list("os bucket list", [])
        bucket = {
            "identifier": "ocid1.bucket.oc1..datadog",
            "display-name": "dd-events-backfill",
            "compartment-id": "ocid1.compartment.oc1..workload",
            "definedTags": {"DatadogManaged": {"marker": "true"}},
            "_region": HOME_REGION,
        }

        cleaner = self.make_cleaner(oci=oci)
        cleaner.cleanup_buckets(
            context(managed_resources=[bucket]),
            HOME_REGION,
        )

        action_ids = {action["id"] for action in cleaner.planned}
        self.assertIn(
            f"bucket:{HOME_REGION}:dd-events-backfill",
            action_ids,
        )
    def test_compartment_inventory_failure_is_not_cached(self):
        cleaner = self.make_cleaner()
        transient_error = cleanup.CommandError(
            ["oci", "iam", "compartment", "list"],
            1,
            "ServiceUnavailable",
        )
        with patch.object(
            cleaner,
            "_list_region",
            side_effect=[
                transient_error,
                [{"id": "instance-compartment", "lifecycle-state": "ACTIVE"}],
            ],
        ) as list_region:
            with self.assertLogs(cleanup.LOGGER, level="WARNING"):
                first = cleaner._compute_compartment_ids(context())
            second = cleaner._compute_compartment_ids(context())

        self.assertEqual([COMPARTMENT, TENANCY], first)
        self.assertEqual(
            ["instance-compartment", COMPARTMENT, TENANCY],
            second,
        )
        self.assertEqual(2, list_region.call_count)

    def test_subnet_deletion_retries_vnic_detach_conflict(self):
        oci = FakeOci()
        responses = iter(
            [
                cleanup.CommandError(
                    ["oci", "network", "subnet", "delete"],
                    1,
                    "Conflict: The Subnet references the VNIC test-vnic",
                ),
                {},
            ]
        )

        def delete_subnet():
            response = next(responses)
            if isinstance(response, Exception):
                raise response
            return response

        oci.add_run("network subnet delete", delete_subnet)
        cleaner = self.make_cleaner(oci=oci)
        with patch("oci_cleanup.domains.network.time.sleep") as sleep:
            cleaner._delete_subnet_after_vnic_detach(HOME_REGION, "test-subnet")

        self.assertEqual(2, len(oci.run_calls))
        sleep.assert_called_once_with(
            cleanup.SUBNET_VNIC_RETRY_INTERVAL_SECONDS
        )

    def test_blocked_subnet_records_stateless_failures_and_stops_dependents(self):
        oci = FakeOci()
        oci.add_list(
            "network vcn list",
            [
                owned(
                    {
                        "id": "dd-vcn-id",
                        "display-name": cleanup.VCN_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        oci.add_list("network nat-gateway list", [])
        oci.add_list("network service-gateway list", [])
        oci.add_list(
            "network subnet list",
            [
                owned(
                    {
                        "id": "blocked-subnet",
                        "display-name": cleanup.SUBNET_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        cleaner = self.make_cleaner(execute=True, oci=oci)
        cleaner.extra_candidates = [
            extra_candidate(
                candidate_id=f"extra:unsupported-vnic:{HOME_REGION}:vnic",
                kind="unsupported-vnic",
                resource_id="vnic",
                container_id="blocked-subnet",
                command=None,
            )
        ]

        cleaner.cleanup_network(context(), HOME_REGION)

        subnet_action = next(
            action
            for action in cleaner.planned
            if action["id"] == f"subnet:{HOME_REGION}:blocked-subnet"
        )
        self.assertEqual("blocked", subnet_action["status"])
        self.assertEqual("blocked-subnet", subnet_action["resource_id"])
        self.assertEqual(HOME_REGION, subnet_action["region"])
        self.assertIsNone(subnet_action["error_code"])
        self.assertIn("Preserve Quickstart subnet", subnet_action["deletion_message"])
        self.assertFalse(
            any(
                "network route-table list" in " ".join(call)
                for call in oci.list_calls
            )
        )
        self.assertTrue(
            any(
                action["id"] == f"network-dependents:{HOME_REGION}"
                and action["status"] == "blocked"
                for action in cleaner.planned
            )
        )
        self.assertEqual(2, len(cleaner.failures))
        subnet_failure, dependents_failure = cleaner.failures
        self.assertEqual(
            {
                "message": subnet_action["description"],
                "resource_id": "blocked-subnet",
                "region": HOME_REGION,
                "error_code": None,
                "deletion_message": subnet_action["description"],
            },
            subnet_failure,
        )
        self.assertEqual("", dependents_failure["resource_id"])
        self.assertEqual(HOME_REGION, dependents_failure["region"])
        self.assertIsNone(dependents_failure["error_code"])
        self.assertIn(
            "Preserve route tables, gateways, and VCN",
            dependents_failure["deletion_message"],
        )

    def test_network_deletes_route_tables_before_owned_gateways(self):
        oci = FakeOci()
        oci.add_list(
            "network vcn list",
            [
                owned(
                    {
                        "id": "dd-vcn-id",
                        "display-name": cleanup.VCN_NAME,
                        "compartment-id": COMPARTMENT,
                        "default-route-table-id": "default-route-table",
                    }
                )
            ],
        )
        oci.add_list(
            "network nat-gateway list",
            [
                owned(
                    {
                        "id": "nat-gateway",
                        "display-name": cleanup.NAT_GATEWAY_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        oci.add_list(
            "network service-gateway list",
            [
                owned(
                    {
                        "id": "service-gateway",
                        "display-name": cleanup.SERVICE_GATEWAY_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        oci.add_list("network subnet list", [])
        oci.add_list(
            "network route-table list",
            [
                {
                    "id": "default-route-table",
                    "display-name": "Default Route Table for dd-vcn",
                    "vcn-id": "dd-vcn-id",
                    "route-rules": [
                        {"network-entity-id": "nat-gateway"},
                        {"network-entity-id": "customer-gateway"},
                    ],
                },
                owned(
                    {
                        "id": "service-route-table",
                        "display-name": "service-gw-route",
                        "vcn-id": "dd-vcn-id",
                        "route-rules": [
                            {"network-entity-id": "service-gateway"}
                        ],
                    }
                ),
            ],
        )
        cleaner = self.make_cleaner(oci=oci, execute=True)
        cleaner.cleanup_network(context(), HOME_REGION)

        commands = [" ".join(call) for call in oci.run_calls]
        update_index = next(
            index
            for index, command in enumerate(commands)
            if "route-table update" in command
        )
        route_delete_index = next(
            index
            for index, command in enumerate(commands)
            if "route-table delete" in command
        )
        gateway_delete_index = next(
            index
            for index, command in enumerate(commands)
            if "service-gateway delete" in command
        )
        self.assertLess(update_index, gateway_delete_index)
        self.assertLess(route_delete_index, gateway_delete_index)
        self.assertIn("customer-gateway", commands[update_index])
        self.assertNotIn(
            '"network-entity-id":"nat-gateway"',
            commands[update_index],
        )

    def test_connector_delete_waits_for_work_request_success(self):
        oci = FakeOci()
        oci.add_list(
            "sch service-connector list",
            [
                owned(
                    {
                        "id": "connector",
                        "display-name": "Datadog connector",
                    }
                )
            ],
        )
        oci.add_list("events rule list", [])
        oci.add_list("streaming admin stream list", [])
        cleaner = self.make_cleaner(oci=oci, execute=True)

        cleaner.cleanup_connectors_events_streams(context(), HOME_REGION)

        delete = next(
            call
            for call in oci.run_calls
            if "service-connector" in call and "delete" in call
        )
        self.assertIn("SUCCEEDED", delete)
        self.assertIn("FAILED", delete)
        self.assertNotIn("DELETED", delete)

    def test_marker_proven_event_rule_outside_target_compartment_is_deleted(self):
        oci = FakeOci()
        oci.add_list("sch service-connector list", [])
        oci.add_list("events rule list", [])
        oci.add_list("streaming admin stream list", [])
        rule = {
            "identifier": "ocid1.eventrule.oc1..datadog",
            "display-name": "Datadog event forwarding",
            "compartment-id": "ocid1.compartment.oc1..workload",
            "definedTags": {"DatadogManaged": {"marker": "true"}},
            "_region": HOME_REGION,
        }
        stream = {
            "identifier": "ocid1.stream.oc1..datadog",
            "display-name": "Datadog event stream",
            "compartment-id": "ocid1.compartment.oc1..workload",
            "definedTags": {"DatadogManaged": {"marker": "true"}},
            "_region": HOME_REGION,
        }
        cleaner = self.make_cleaner(oci=oci, execute=True)
        cleaner.cleanup_connectors_events_streams(
            context(managed_resources=[rule, stream]), HOME_REGION
        )
        self.assertTrue(
            any(
                action["id"]
                == f"event-rule:{HOME_REGION}:ocid1.eventrule.oc1..datadog"
                for action in cleaner.planned
            )
        )
        event_delete = next(
            call for call in oci.run_calls if "events" in call and "delete" in call
        )
        stream_delete = next(
            call for call in oci.run_calls if "streaming" in call and "delete" in call
        )
        self.assertEqual("DELETED", event_delete[-1])
        self.assertEqual("DELETED", stream_delete[-1])

    def test_kms_actions_use_minimum_buffered_deletion_times(self):
        oci = FakeOci()
        oci.add_list(
            "vault secret list",
            [
                owned(
                    {
                        "id": "secret",
                        "secret-name": cleanup.SECRET_NAME,
                        "name": cleanup.SECRET_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        oci.add_list(
            "kms management vault list",
            [
                owned(
                    {
                        "id": "vault",
                        "display-name": cleanup.VAULT_NAME,
                        "compartment-id": COMPARTMENT,
                        "management-endpoint": "https://kms.example",
                    }
                )
            ],
        )
        oci.add_list(
            "kms management key list",
            [
                owned(
                    {
                        "id": "key",
                        "display-name": cleanup.KEY_NAME,
                        "compartment-id": COMPARTMENT,
                    }
                )
            ],
        )
        cleaner = self.make_cleaner(oci=oci)
        cleaner.cleanup_kms(context(), HOME_REGION)
        times_by_kind = {
            action["id"].split(":", 1)[0]: action.get("deletion_time")
            for action in cleaner.planned
            if action["id"].startswith(("secret:", "kms-key:", "kms-vault:"))
        }
        self.assertNotEqual(times_by_kind["secret"], times_by_kind["kms-key"])
        self.assertEqual(times_by_kind["kms-key"], times_by_kind["kms-vault"])
        self.assertTrue(cleaner.kms_pending)

    def test_run_cleans_regions_concurrently(self):
        cleaner = self.make_cleaner(
            args=SimpleNamespace(region_workers=2)
        )
        regions = [HOME_REGION, "us-phoenix-1"]
        barrier = threading.Barrier(len(regions))
        completed = []

        cleaner.discover = lambda: context(regions=regions)

        def cleanup_region(_context, region):
            barrier.wait(timeout=1)
            completed.append(region)

        cleaner.cleanup_region = cleanup_region

        with contextlib.redirect_stdout(io.StringIO()):
            result = cleaner.run()

        self.assertEqual(0, result)
        self.assertCountEqual(regions, completed)


if __name__ == "__main__":
    unittest.main()
