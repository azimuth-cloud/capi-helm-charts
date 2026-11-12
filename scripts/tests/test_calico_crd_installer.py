#!/usr/bin/env python3
"""Offline contract tests for the canonical Calico CRD installer.

Run with: python3 -m unittest discover -s scripts/tests -p 'test_*.py'
Only temporary fake kubectl/rm executables are invoked. No Kubernetes API,
manifest URL, registry, or Helm repository is contacted.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
INSTALLER = REPOSITORY / "charts/cluster-addons/files/install-calico-crds.sh"
MANIFEST = """apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: clusternetworkpolicies.policy.networking.k8s.io
spec:
  group: policy.networking.k8s.io
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: installations.operator.tigera.io
spec:
  group: operator.tigera.io
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: first.crd.projectcalico.org
spec:
  group: crd.projectcalico.org
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: second.crd.projectcalico.org
spec:
  group: crd.projectcalico.org
"""
RESOURCE_PREFIX = "customresourcedefinition.apiextensions.k8s.io/"
FIRST_RESOURCE = RESOURCE_PREFIX + "first.crd.projectcalico.org"
SECOND_RESOURCE = RESOURCE_PREFIX + "second.crd.projectcalico.org"
OPERATOR_RESOURCE = RESOURCE_PREFIX + "installations.operator.tigera.io"
POLICY_RESOURCE = RESOURCE_PREFIX + "clusternetworkpolicies.policy.networking.k8s.io"
ALL_RESOURCES = [FIRST_RESOURCE, SECOND_RESOURCE, OPERATOR_RESOURCE, POLICY_RESOURCE]

# Each fake command records its arguments and the actual manifest file it sees.
# The same program is installed as kubectl and rm; no shell or YAML dependency
# is needed to inspect the sequence, target file, or cleanup behaviour.
COMMAND_STUB = r'''
import json
import os
from pathlib import Path
import re
import sys

tool = Path(sys.argv[0]).name
arguments = sys.argv[1:]
record = {"tool": tool, "arguments": arguments}
if tool == "kubectl" and "-f" in arguments:
    filename = arguments[arguments.index("-f") + 1]
    record["filename"] = filename
    record["file_exists"] = Path(filename).is_file()
    record["manifest"] = Path(filename).read_text() if record["file_exists"] else None
with open(os.environ["CALICO_TEST_TRACE"], "a", encoding="utf-8") as log:
    log.write(json.dumps(record) + "\n")

if tool == "rm":
    if os.environ["CALICO_TEST_CLEANUP_FAILURE"] == "yes":
        sys.exit(97)
    for name in arguments:
        if name.startswith("-"):
            continue
        target = Path(name)
        assert target.parent == Path(os.environ["TMPDIR"]), target
        try:
            target.unlink()
        except FileNotFoundError:
            pass
    sys.exit(0)

stage = arguments[0] if arguments else ""
scenario = os.environ["CALICO_TEST_SCENARIO"]
if stage == "create":
    dry_run = "--dry-run=client" in arguments
    output = arguments[arguments.index("-o") + 1] if "-o" in arguments else ""
    if dry_run and output == "yaml":
        if scenario == "empty_render":
            sys.exit(0)
        manifest = Path(os.environ["CALICO_TEST_MANIFEST"]).read_text()
        if scenario == "partial_render_failure":
            sys.stdout.write(manifest.split("---\n", 1)[0])
            sys.exit(17)
        sys.stdout.write(manifest)
        sys.exit(0)
    if dry_run and output.startswith("jsonpath="):
        # kubectl create flattens its input and invokes its printer once per
        # object. A per-object JSONPath therefore sees no .items collection.
        if ".items" in output or scenario == "empty_json_render":
            sys.exit(0)
        documents = record["manifest"].strip().split("---\n")
        for index, document in enumerate(documents):
            name = re.search(r"^  name: (.+)$", document, re.MULTILINE).group(1)
            group = re.search(r"^  group: (.+)$", document, re.MULTILINE).group(1)
            obj = {"apiVersion": "apiextensions.k8s.io/v1", "kind": "CustomResourceDefinition",
                   "metadata": {"name": name}, "spec": {"group": group}}
            prefix = group + "\t" if "{.spec.group}" in output else ""
            print(prefix + json.dumps(obj, separators=(",", ":")))
            if scenario == "json_render_failure" and index == 0:
                sys.exit(19)
        sys.exit(0)
    if dry_run and output == "name":
        if scenario == "name_render_failure":
            sys.exit(21)
        obj = json.loads(record["manifest"])
        assert obj["kind"] == "CustomResourceDefinition"
        print("customresourcedefinition.apiextensions.k8s.io/" + obj["metadata"]["name"])
        sys.exit(0)
    if not dry_run:
        assert "--field-manager=calico-crds-bootstrap" in arguments, arguments
        obj = json.loads(record["manifest"])
        resource = "customresourcedefinition.apiextensions.k8s.io/" + obj["metadata"]["name"]
        if scenario == "real_create_failure" and resource == os.environ["CALICO_TEST_FAIL_RESOURCE"]:
            sys.exit(37)
        state_path = Path(os.environ["CALICO_TEST_STATE"])
        state = json.loads(state_path.read_text())
        if resource in state:
            sys.exit(38)  # AlreadyExists must not be mistaken for success.
        state.append(resource)
        state_path.write_text(json.dumps(state))
        print(resource + " created")
        sys.exit(0)
    sys.exit(90)
if stage == "get":
    assert "--ignore-not-found" in arguments and "-o" in arguments
    resource = arguments[1]
    if scenario == "get_failure" and resource == os.environ["CALICO_TEST_FAIL_RESOURCE"]:
        sys.exit(31)
    state = json.loads(Path(os.environ["CALICO_TEST_STATE"]).read_text())
    if resource in state:
        print(resource)
    sys.exit(0)
if stage == "wait":
    sys.exit(29 if scenario == "wait_failure" else 0)
# Includes delete: the installer must not delete RBAC or CRDs itself.
sys.exit(91)
'''


class CalicoCrdInstallerTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(INSTALLER.is_file(), f"Canonical installer missing: {INSTALLER}")
        # Spaces exercise quoting of PATH entries, mktemp output, and -f values.
        self.temporary = tempfile.TemporaryDirectory(prefix="calico installer test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin_directory = self.root / "fake commands"
        self.bin_directory.mkdir()
        self.temp_directory = self.root / "temporary manifests"
        self.temp_directory.mkdir()
        self.trace = self.root / "trace.jsonl"
        self.manifest = self.root / "rendered fixture.yaml"
        self.manifest.write_text(MANIFEST)
        self.state = self.root / "existing resources.json"
        self.state.write_text("[]")
        for tool in ("kubectl", "rm"):
            executable = self.bin_directory / tool
            executable.write_text(f"#!{sys.executable}\n" + COMMAND_STUB)
            executable.chmod(0o700)

    def run_installer(self, scenario="success", version="v3.32.2", cleanup_failure=False,
                      existing=None, fail_resource=FIRST_RESOURCE):
        if self.trace.exists():
            self.trace.unlink()
        if existing is not None:
            self.state.write_text(json.dumps(existing))
        environment = dict(os.environ)
        environment.pop("CALICO_CRD_VERSION", None)
        environment.update({
            "PATH": str(self.bin_directory) + os.pathsep + environment.get("PATH", os.defpath),
            "TMPDIR": str(self.temp_directory),
            "CALICO_TEST_TRACE": str(self.trace),
            "CALICO_TEST_MANIFEST": str(self.manifest),
            "CALICO_TEST_SCENARIO": scenario,
            "CALICO_TEST_CLEANUP_FAILURE": "yes" if cleanup_failure else "no",
            "CALICO_TEST_STATE": str(self.state),
            "CALICO_TEST_FAIL_RESOURCE": fail_resource,
        })
        if version is not None:
            environment["CALICO_CRD_VERSION"] = version
        result = subprocess.run(
            ["/bin/sh", str(INSTALLER)], cwd=self.root, env=environment,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10,
        )
        calls = [json.loads(line) for line in self.trace.read_text().splitlines()] if self.trace.exists() else []
        return result, calls

    @staticmethod
    def kubectl_calls(calls):
        return [call for call in calls if call["tool"] == "kubectl"]

    def assert_steps(self, calls, expected):
        self.assertEqual([call["arguments"][0] for call in self.kubectl_calls(calls)], expected)

    def assert_cleaned_up(self):
        self.assertEqual(list(self.temp_directory.iterdir()), [], "Temporary rendered manifest was not removed")

    @classmethod
    def real_creates(cls, calls):
        return [call for call in cls.kubectl_calls(calls)
                if call["arguments"][0] == "create" and "--dry-run=client" not in call["arguments"]]

    def assert_bootstrap_does_not_apply(self, calls):
        self.assertNotIn("apply", [call["arguments"][0] for call in self.kubectl_calls(calls)])
        self.assertFalse(any("--force-conflicts" in call["arguments"] for call in self.kubectl_calls(calls)))

    def assert_waits_for_all_rendered_targets(self, calls):
        waits = [call for call in self.kubectl_calls(calls) if call["arguments"][0] == "wait"]
        full_waits = [call for call in waits if call["manifest"] == self.manifest.read_text()]
        self.assertEqual(len(full_waits), 1)
        self.assertEqual(waits[-1], full_waits[0], "All-target wait must be the final wait")
        for call in waits:
            self.assertIn("--for=condition=Established", call["arguments"])
            self.assertNotIn("--all", call["arguments"])

    def test_requested_version_selects_the_manifest_url(self):
        for version in ("v3.32.2", "v3.33.0"):
            with self.subTest(version=version):
                result, calls = self.run_installer(version=version)
                self.assertEqual(result.returncode, 0, result.stderr)
                create = self.kubectl_calls(calls)[0]["arguments"]
                self.assertEqual(create[create.index("-f") + 1], f"https://raw.githubusercontent.com/projectcalico/calico/{version}/manifests/v1_crd_projectcalico_org.yaml")
                self.assert_cleaned_up()

    def test_partial_render_failure_never_writes_crds(self):
        result, calls = self.run_installer(scenario="partial_render_failure")
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assert_steps(calls, ["create"])
        self.assert_cleaned_up()

    def test_empty_render_never_writes_crds(self):
        result, calls = self.run_installer(scenario="empty_render")
        self.assertNotEqual(result.returncode, 0)
        self.assert_steps(calls, ["create"])
        self.assert_cleaned_up()

    def test_established_timeout_is_not_reported_as_success(self):
        result, calls = self.run_installer(scenario="wait_failure")
        self.assertEqual(result.returncode, 29, result.stderr)
        self.assert_steps(calls, ["create", "create", "create", "get", "create", "wait"])
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_cleaned_up()

    def test_missing_version_fails_before_any_external_command(self):
        result, calls = self.run_installer(version=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.kubectl_calls(calls), [])
        self.assert_cleaned_up()

    def test_invalid_version_fails_before_any_external_command(self):
        for version in ("", "latest", "3.33.0", "--help"):
            with self.subTest(version=version):
                result, calls = self.run_installer(version=version)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.kubectl_calls(calls), [])
                self.assert_cleaned_up()

    def test_cleanup_failure_does_not_mask_create_failure(self):
        result, calls = self.run_installer(scenario="real_create_failure", cleanup_failure=True)
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assert_steps(calls, ["create", "create", "create", "get", "create"])
        self.assertTrue(any(call["tool"] == "rm" for call in calls), "Cleanup failure was not exercised")
        self.assertGreaterEqual(len(list(self.temp_directory.iterdir())), 1)

    def test_cleanup_failure_does_not_replace_success(self):
        result, calls = self.run_installer(cleanup_failure=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_waits_for_all_rendered_targets(calls)
        self.assertTrue(any(call["tool"] == "rm" for call in calls), "Cleanup failure was not exercised")
        self.assertGreaterEqual(len(list(self.temp_directory.iterdir())), 1)

    def test_bootstrap_skips_every_existing_crd_without_writing(self):
        existing = list(ALL_RESOURCES)
        result, calls = self.run_installer(existing=existing)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.real_creates(calls), [])
        self.assertEqual(json.loads(self.state.read_text()), existing)
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_waits_for_all_rendered_targets(calls)
        self.assert_cleaned_up()

    def test_bootstrap_creates_only_missing_crds(self):
        result, calls = self.run_installer(
            existing=[FIRST_RESOURCE, OPERATOR_RESOURCE, POLICY_RESOURCE],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        creates = self.real_creates(calls)
        self.assertEqual(len(creates), 1)
        self.assertEqual(json.loads(creates[0]["manifest"])["metadata"]["name"], "second.crd.projectcalico.org")
        self.assertCountEqual(json.loads(self.state.read_text()), ALL_RESOURCES)
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_waits_for_all_rendered_targets(calls)
        self.assert_cleaned_up()

    def test_bootstrap_is_the_default_and_creates_all_absent_crds(self):
        result, calls = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.real_creates(calls)), len(ALL_RESOURCES))
        self.assertEqual(json.loads(self.state.read_text()), ALL_RESOURCES)
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_waits_for_all_rendered_targets(calls)
        self.assert_cleaned_up()

    def test_bootstrap_get_error_is_not_treated_as_not_found(self):
        result, calls = self.run_installer(scenario="get_failure")
        self.assertEqual(result.returncode, 31, result.stderr)
        self.assertEqual(self.real_creates(calls), [])
        self.assertNotIn("wait", [call["arguments"][0] for call in self.kubectl_calls(calls)])
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_cleaned_up()

    def test_bootstrap_create_error_preserves_status_and_does_not_wait(self):
        result, calls = self.run_installer(scenario="real_create_failure")
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertEqual(len(self.real_creates(calls)), 1)
        self.assertNotIn("wait", [call["arguments"][0] for call in self.kubectl_calls(calls)])
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_cleaned_up()

    def test_bootstrap_retry_skips_crd_created_by_the_failed_attempt(self):
        first, first_calls = self.run_installer(
            scenario="real_create_failure", fail_resource=SECOND_RESOURCE,
        )
        self.assertEqual(first.returncode, 37, first.stderr)
        self.assertEqual(len(self.real_creates(first_calls)), 2)
        self.assertEqual(json.loads(self.state.read_text()), [FIRST_RESOURCE])
        self.assert_cleaned_up()
        second, second_calls = self.run_installer()
        self.assertEqual(second.returncode, 0, second.stderr)
        creates = self.real_creates(second_calls)
        self.assertEqual([json.loads(call["manifest"])["metadata"]["name"] for call in creates],
                         ["second.crd.projectcalico.org", "installations.operator.tigera.io",
                          "clusternetworkpolicies.policy.networking.k8s.io"])
        self.assertEqual(json.loads(self.state.read_text()), ALL_RESOURCES)
        first_filename = self.kubectl_calls(first_calls)[1]["filename"]
        second_filename = self.kubectl_calls(second_calls)[1]["filename"]
        self.assertNotEqual(first_filename, second_filename)
        self.assert_bootstrap_does_not_apply(second_calls)
        self.assert_cleaned_up()

    def test_bootstrap_partial_json_render_failure_does_not_write_crds(self):
        result, calls = self.run_installer(scenario="json_render_failure")
        self.assertEqual(result.returncode, 19, result.stderr)
        self.assertEqual(self.real_creates(calls), [])
        self.assertEqual([call for call in self.kubectl_calls(calls) if call["arguments"][0] == "get"], [])
        self.assertNotIn("wait", [call["arguments"][0] for call in self.kubectl_calls(calls)])
        self.assert_cleaned_up()

    def test_bootstrap_empty_json_render_does_not_report_success(self):
        result, calls = self.run_installer(scenario="empty_json_render")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.real_creates(calls), [])
        self.assertNotIn("wait", [call["arguments"][0] for call in self.kubectl_calls(calls)])
        self.assert_cleaned_up()

    def test_bootstrap_name_render_failure_does_not_write_crds(self):
        result, calls = self.run_installer(scenario="name_render_failure")
        self.assertEqual(result.returncode, 21, result.stderr)
        self.assertEqual(self.real_creates(calls), [])
        self.assertNotIn("wait", [call["arguments"][0] for call in self.kubectl_calls(calls)])
        self.assert_cleaned_up()

    def test_bootstrap_orders_and_establishes_all_three_upstream_groups(self):
        # The downloaded fixture deliberately puts policy, then operator, CRDs
        # before Calico v1 CRDs. Bootstrap must establish the v1 API first.
        result, calls = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        sequence = []
        for call in self.kubectl_calls(calls):
            stage = call["arguments"][0]
            is_real_create = stage == "create" and "--dry-run=client" not in call["arguments"]
            if is_real_create or (stage == "wait" and call["manifest"] != MANIFEST):
                sequence.append((stage, json.loads(call["manifest"])["metadata"]["name"]))
        self.assertEqual(sequence, [
            ("create", "first.crd.projectcalico.org"),
            ("wait", "first.crd.projectcalico.org"),
            ("create", "second.crd.projectcalico.org"),
            ("wait", "second.crd.projectcalico.org"),
            ("create", "installations.operator.tigera.io"),
            ("wait", "installations.operator.tigera.io"),
            ("create", "clusternetworkpolicies.policy.networking.k8s.io"),
            ("wait", "clusternetworkpolicies.policy.networking.k8s.io"),
        ])
        self.assert_waits_for_all_rendered_targets(calls)
        self.assert_cleaned_up()

    def test_bootstrap_refuses_an_unexpected_crd_group(self):
        self.manifest.write_text(MANIFEST.replace("group: operator.tigera.io", "group: aaa.invalid", 1))
        result, calls = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.real_creates(calls), [])
        self.assert_bootstrap_does_not_apply(calls)
        self.assert_cleaned_up()


if __name__ == "__main__":
    unittest.main()
