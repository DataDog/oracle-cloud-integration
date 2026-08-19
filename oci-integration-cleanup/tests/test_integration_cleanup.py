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
from oci_cleanup.resources import resource_field


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
