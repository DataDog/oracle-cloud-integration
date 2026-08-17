import argparse
import contextlib
import io
import json
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


TENANCY = "ocid1.tenancy.oc1..test"
COMPARTMENT = "ocid1.compartment.oc1..datadog"
HOME_REGION = "us-ashburn-1"


class FakeOci:
    def __init__(self):
        self.list_responses = {}
        self.run_responses = {}
        self.list_calls = []
        self.run_calls = []

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
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)

    def test_facade_reexports_public_package_api(self):
        self.assertEqual(
            set(cleanup.__all__),
            {*oci_cleanup.__all__, "QuickstartCleanup", "parse_args", "main"},
        )
        for name in oci_cleanup.__all__:
            self.assertIs(getattr(oci_cleanup, name), getattr(cleanup, name))

    def make_cleaner(self, *, execute=False, oci=None, args=None):
        manifest_path = pathlib.Path(self.tempdir.name) / "manifest.json"
        manifest = cleanup.Manifest.load(manifest_path, TENANCY)
        default_args = SimpleNamespace(
            execute=execute,
            tenancy_id=TENANCY,
            compartment_id=COMPARTMENT,
            domain_endpoint=None,
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
            manifest=manifest,
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

    def test_execute_requires_confirmation_and_manifest(self):
        common = [
            "--tenancy-id",
            TENANCY,
            "--execute",
        ]
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                cleanup.parse_args(common)
            with self.assertRaises(SystemExit):
                cleanup.parse_args([*common, "--confirm-tenancy-id", TENANCY])
        args = cleanup.parse_args(
            [
                *common,
                "--confirm-tenancy-id",
                TENANCY,
                "--state-file",
                str(pathlib.Path(self.tempdir.name) / "state.json"),
            ]
        )
        self.assertTrue(args.execute)

    def test_dry_run_requires_only_tenancy(self):
        args = cleanup.parse_args(["--tenancy-id", TENANCY])
        self.assertFalse(args.execute)
        self.assertEqual(1, args.region_workers)

    def test_region_workers_must_be_positive(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                cleanup.parse_args(
                    [
                        "--tenancy-id",
                        TENANCY,
                        "--region-workers",
                        "0",
                    ]
                )
        args = cleanup.parse_args(
            [
                "--tenancy-id",
                TENANCY,
                "--region-workers",
                "4",
            ]
        )
        self.assertEqual(4, args.region_workers)

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

    def test_completed_manifest_action_is_not_repeated(self):
        cleaner = self.make_cleaner(execute=True)
        cleaner.manifest.record_action("delete:test", "Delete test", "completed")
        invoked = []
        result = cleaner.action(
            "delete:test",
            "Delete test",
            function=lambda: invoked.append(True),
        )
        self.assertTrue(result)
        self.assertEqual([], invoked)
        self.assertEqual("already-completed", cleaner.planned[0]["status"])

    def test_completed_action_retries_when_live_resource_still_exists(self):
        cleaner = self.make_cleaner(execute=True)
        cleaner.manifest.record_action("delete:test", "Delete test", "completed")
        invoked = []

        result = cleaner.action(
            "delete:test",
            "Delete test",
            function=lambda: invoked.append(True),
            retry_completed=True,
        )

        self.assertTrue(result)
        self.assertEqual([True], invoked)
        self.assertEqual("completed", cleaner.planned[0]["status"])

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
