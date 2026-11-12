"""Exercise the updater's version and image contracts without network access."""

import copy
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "charts" / "cluster-addons"
HELM = shutil.which("helm")
SEPARATE_COMPONENTS = (
    "apiserver", "cni", "csi", "kube-controllers", "node",
    "node-driver-registrar", "pod2daemon-flexvol", "typha",
    "goldmane", "whisker", "whisker-backend",
)
COMBINED_COMPONENTS = ("calico", "node", "third-party-cni-plugins", "whisker")


def set_value(values, path, value):
    keys = path.split(".")
    target = values
    for key in keys[:-1]:
        target = target[key]
    target[keys[-1]] = value


class CalicoDependenciesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = yaml.safe_load(
            (ROOT / ".github/workflows/update-addons.yml").read_text()
        )
        cls.job = cls.workflow["jobs"]["propose_update_pr"]
        cls.steps = cls.job["steps"]
        cls.matrix = cls.job["strategy"]["matrix"]["include"]
        cls.calico = next(item for item in cls.matrix if item["key"] == "calico")
        cls.values = yaml.safe_load((CHART / "values.yaml").read_text())
        current = cls.values["cni"]["calico"]["chart"]["version"]
        major, minor, _ = current.lstrip("v").split(".", 2)
        cls.future_version = f"v{major}.{int(minor) + 1}.1"

    def update_values(self, matrix, version):
        """Apply the config-update action inputs, as the real updater would."""
        values = copy.deepcopy(self.values)
        updates = [
            step for step in self.steps
            if step.get("uses", "").startswith(
                "azimuth-cloud/github-actions/config-update@"
            )
            and step.get("if") == (
                "${{ matrix.key == 'calico' }}" if matrix["key"] == "calico"
                else "${{ matrix.key != 'calico' }}"
            )
        ]
        self.assertEqual(len(updates), 1, "each addon must select one update step")
        instructions = updates[0]["with"]["updates"]
        instructions = instructions.replace("${{ matrix.path }}", matrix["path"])
        instructions = instructions.replace("${{ steps.next.outputs.version }}", version)
        self.assertNotIn("${{", instructions)
        for line in instructions.splitlines():
            if line.strip():
                path, value = line.split("=", 1)
                set_value(values, path, value)
        return values

    def render(self, values):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            values_file = temporary / "values.yaml"
            values_file.write_text(yaml.safe_dump(values))
            environment = dict(os.environ)
            for kind in ("CONFIG", "CACHE", "DATA"):
                environment[f"HELM_{kind}_HOME"] = str(temporary / kind.lower())
            return subprocess.run(
                [HELM, "template", "test", str(CHART), "-f", str(values_file)],
                env=environment, text=True, capture_output=True, check=False,
            )

    @unittest.skipUnless(HELM, "helm is required to exercise actual chart rendering")
    def test_future_update_renders_matching_operator_and_installer_versions(self):
        updated = self.update_values(self.calico, self.future_version)
        result = self.render(updated)
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = list(yaml.safe_load_all(result.stdout))
        operator = next(
            item for item in resources
            if item and item["kind"] == "HelmRelease"
            and item["metadata"]["name"] == "test-cni-calico"
        )
        self.assertEqual(operator["spec"]["chart"]["version"], self.future_version)
        installer = next(
            item for item in resources
            if item and item["kind"] == "Manifests"
            and item["metadata"]["name"] == "test-cni-calico-crds"
        )
        manifests = installer["spec"]["manifestSources"][0]["template"]
        job = next(
            item for item in yaml.safe_load_all(manifests)
            if item and item["kind"] == "Job"
        )
        environment = {
            item["name"]: item["value"]
            for item in job["spec"]["template"]["spec"]["containers"][0]["env"]
        }
        self.assertEqual(environment["CALICO_CRD_VERSION"], self.future_version)

    @unittest.skipUnless(HELM, "helm is required to exercise actual chart rendering")
    def test_operator_only_update_is_rejected_by_actual_chart(self):
        values = copy.deepcopy(self.values)
        values["cni"]["calico"]["chart"]["version"] = self.future_version
        result = self.render(values)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("crdChartVersion to match", result.stderr)

    def test_other_addon_updates_change_only_their_own_chart_version(self):
        for matrix in self.matrix:
            if matrix["key"] == "calico":
                continue
            with self.subTest(addon=matrix["key"]):
                expected = copy.deepcopy(self.values)
                set_value(expected, matrix["path"] + ".version", self.future_version)
                self.assertEqual(self.update_values(matrix, self.future_version), expected)

    def test_manifest_preflight_fails_before_updates_and_pr(self):
        preflight = next(
            step for step in self.steps
            if step.get("name") == "Verify the Calico CRD manifest is available"
        )
        self.assertEqual(preflight["if"], "${{ matrix.key == 'calico' }}")
        position = self.steps.index(preflight)
        for index, step in enumerate(self.steps):
            if any(name in step.get("uses", "") for name in (
                "/config-update@", "/create-pull-request@",
            )):
                self.assertLess(position, index)
        environment = dict(os.environ, CALICO_TARGET_VERSION=self.future_version)
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            curl = temporary / "curl"
            curl.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$@" > "$CURL_ARGUMENTS_FILE"\n'
                'exit "${CURL_EXIT_CODE:-0}"\n'
            )
            curl.chmod(0o755)
            arguments = temporary / "arguments"
            environment["PATH"] = directory + os.pathsep + environment["PATH"]
            environment["CURL_ARGUMENTS_FILE"] = str(arguments)
            for exit_code in (0, 42):
                with self.subTest(curl_exit_code=exit_code):
                    environment["CURL_EXIT_CODE"] = str(exit_code)
                    result = subprocess.run(
                        ["bash", "-e", "-o", "pipefail", "-c", preflight["run"]],
                        env=environment, capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, exit_code, result.stderr)
                    self.assertEqual(arguments.read_text().splitlines(), [
                        "--fail", "--silent", "--show-error",
                        f"https://raw.githubusercontent.com/projectcalico/calico/{self.future_version}/manifests/v1_crd_projectcalico_org.yaml",
                        "--output", "/dev/null",
                    ])

    def runtime_images(self, version):
        step = next(item for item in self.steps if item.get("id") == "calico-images")
        self.assertEqual(step["if"], "${{ matrix.key == 'calico' }}")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            environment = dict(os.environ, CALICO_TARGET_VERSION=version,
                               GITHUB_OUTPUT=str(output))
            result = subprocess.run(
                ["bash", "-e", "-o", "pipefail", "-c", step["run"]],
                env=environment, capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = output.read_text().splitlines()
            self.assertEqual(lines[0], "images<<EOF")
            self.assertEqual(lines[-1], "EOF")
        return set(lines[1:-1])

    def test_current_mirror_matches_updater(self):
        manifests = yaml.safe_load((ROOT / "skopeo-manifests/calico.yaml").read_text())
        actual = {
            f"{registry}/{name}:{tag}"
            for registry, configuration in manifests.items()
            for name, tags in configuration["images"].items()
            for tag in tags
        }
        # The chart exposes the operator image; the other Linux component images
        # are created dynamically by the operator and need explicit mirror entries.
        target_operators = {
            image for image in actual
            if image.startswith("quay.io/tigera/operator:")
        }
        self.assertEqual(len(target_operators), 1)
        # Its tag is extracted from the upstream chart, not coupled to Calico's
        # version number; allow later updater PRs to advance it independently.
        version = self.values["cni"]["calico"]["chart"]["version"]
        expected = self.runtime_images(version) | target_operators
        self.assertEqual(actual, expected)

    def test_mirror_selects_components_for_each_version(self):
        for version, components in (
            ("v3.32.2", SEPARATE_COMPONENTS),
            ("v3.32.3", SEPARATE_COMPONENTS),
            ("v3.33.0", COMBINED_COMPONENTS),
            ("v3.34.1", COMBINED_COMPONENTS),
        ):
            with self.subTest(version=version):
                self.assertEqual(self.runtime_images(version), {
                    f"quay.io/calico/{name}:{version}" for name in components
                })

    def test_mirror_includes_chart_and_runtime_images(self):
        manifest = next(
            step for step in self.steps
            if step.get("uses", "").startswith("azimuth-cloud/github-actions/skopeo-manifest@")
        )
        self.assertIn("${{ steps.extract-images.outputs.images }}", manifest["with"]["images"])
        self.assertIn("${{ steps.calico-images.outputs.images }}", manifest["with"]["images"])


if __name__ == "__main__":
    unittest.main()
