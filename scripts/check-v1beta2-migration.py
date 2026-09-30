#!/usr/bin/env python3
"""
Compare old and current chart output to check migration compatibility.
Schema validation runs separately in CI.
This does not test API-server conversion or live rollouts.
Requires PyYAML.
Generated files are saved in --output-dir.
"""

import argparse
import copy
import datetime
from decimal import Decimal
import io
import json
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

import yaml


KINDS = {"Cluster", "OpenStackCluster", "OpenStackMachineTemplate",
         "KubeadmControlPlane", "KubeadmConfigTemplate", "MachineDeployment",
         "MachineHealthCheck"}
TEMPLATES = {"OpenStackMachineTemplate", "KubeadmConfigTemplate"}
ARG_PATHS = ["clusterConfiguration.apiServer.extraArgs",
             "clusterConfiguration.controllerManager.extraArgs",
             "clusterConfiguration.scheduler.extraArgs",
             "clusterConfiguration.etcd.local.extraArgs",
             "initConfiguration.nodeRegistration.kubeletExtraArgs",
             "joinConfiguration.nodeRegistration.kubeletExtraArgs"]


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True,
                          capture_output=True, **kwargs)


def get(obj, path, default=None):
    for key in path.split("."):
        if not isinstance(obj, dict) or key not in obj:
            return default
        obj = obj[key]
    return obj


def archive(repo, ref, target):
    commit = run(["git", "-C", repo, "rev-parse", "--verify", ref + "^{commit}"]).stdout.decode().strip()
    data = run(["git", "-C", repo, "archive", commit, "charts/openstack-cluster",
                "charts/cluster-addons"]).stdout
    target.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as stream:
        for item in stream.getmembers():
            resolved = (target / item.name).resolve()
            if target.resolve() not in resolved.parents or item.issym() or item.islnk():
                raise ValueError("Unsafe archive entry: " + item.name)
        stream.extractall(target)
    return commit


def prepare(helm, directory, log):
    result = run([helm, "dependency", "build", directory / "charts/openstack-cluster"])
    log.write_bytes(result.stdout + result.stderr)


def render(helm, directory, values, output):
    command = [helm, "template", "foo", directory / "charts/openstack-cluster",
               "--namespace", "default"]
    for item in values:
        command.extend(["-f", item])
    result = subprocess.run([str(x) for x in command], capture_output=True)
    output.write_bytes(result.stdout)
    output.with_suffix(".stderr.log").write_bytes(result.stderr)
    if result.returncode:
        raise AssertionError("Helm failed: " + str(output.with_suffix(".stderr.log")))
    documents = [doc for doc in yaml.safe_load_all(result.stdout) if doc]
    return {(doc["kind"], doc["metadata"]["name"]): doc for doc in documents}


def refs(obj):
    """Find reference targets regardless of API version or field location."""
    result = []
    if isinstance(obj, dict):
        if "kind" in obj and "name" in obj and ("apiVersion" in obj or "apiGroup" in obj):
            group = obj.get("apiGroup", obj.get("apiVersion", "").split("/")[0])
            result.append((group, obj["kind"], obj["name"]))
        else:
            for value in obj.values():
                result.extend(refs(value))
    elif isinstance(obj, list):
        for value in obj:
            result.extend(refs(value))
    return sorted(result)


def args_in_order(value):
    # CAPI converts legacy maps to a list in sorted key order.
    # Preserve list order and duplicates so that changes to either fail the comparison.
    if isinstance(value, dict):
        return [{"name": key, "value": value[key]} for key in sorted(value)]
    return value or []


def checksums(resource):
    return {k: v for k, v in resource["metadata"].get("annotations", {}).items()
            if k.endswith("/template-checksum")}


def duration_seconds(value):
    """Convert test durations to seconds without using the chart helpers."""
    if value is None:
        return None
    units = {"h": Decimal(3600), "m": Decimal(60), "s": Decimal(1),
             "ms": Decimal("0.001"), "us": Decimal("0.000001"),
             "ns": Decimal("0.000000001")}
    parts = re.findall(r"(\d+(?:\.\d+)?)(ms|us|ns|h|m|s)", str(value))
    total = sum((Decimal(number) * units[unit] for number, unit in parts), Decimal(0))
    return min(int(total), 2147483647)


def bootstrap_spec(resource):
    if resource["kind"] == "KubeadmControlPlane":
        return get(resource, "spec.kubeadmConfigSpec", {})
    return get(resource, "spec.template.spec", {})


def with_defaults(records, defaults):
    """Fill omitted fields with their API defaults before comparing."""
    return [dict(defaults, **record) for record in (records or [])]


def compare(old, new):
    errors = []

    def same(label, before, after):
        if before != after:
            errors.append({"check": label, "old": before, "new": after})

    old_keys = {key for key in old if key[0] in KINDS}
    new_keys = {key for key in new if key[0] in KINDS}
    same("resource names and counts", sorted(old_keys), sorted(new_keys))
    for key in sorted(new_keys):
        same(str(key) + " apiVersion", "v1beta2", new[key]["apiVersion"].split("/")[-1])
    for key in sorted(old_keys & new_keys):
        before, after = old[key], new[key]
        label = "/".join(key)
        same(label + " references", refs(before["spec"]), refs(after["spec"]))
        if key[0] in TEMPLATES:
            same(label + " checksum", checksums(before), checksums(after))
        if key[0] in {"KubeadmControlPlane", "MachineDeployment"}:
            same(label + " replicas", before["spec"].get("replicas"), after["spec"].get("replicas"))
            if key[0] == "KubeadmControlPlane":
                old_machine = get(before, "spec.machineTemplate")
                new_machine = get(after, "spec.machineTemplate.spec")
                same(label + " Kubernetes version", get(before, "spec.version"), get(after, "spec.version"))
                same(label + " rollout strategy", get(before, "spec.rolloutStrategy"), get(after, "spec.rollout.strategy"))
                same(label + " certificate rollout", get(before, "spec.rolloutBefore"), get(after, "spec.rollout.before"))
            else:
                old_machine = get(before, "spec.template.spec")
                new_machine = get(after, "spec.template.spec")
                same(label + " Kubernetes version", old_machine.get("version"), new_machine.get("version"))
                same(label + " failure domain", old_machine.get("failureDomain"), new_machine.get("failureDomain"))
                same(label + " rollout type", get(before, "spec.strategy.type"), get(after, "spec.rollout.strategy.type"))
                for field in ("maxSurge", "maxUnavailable"):
                    same(label + " rollout " + field, get(before, "spec.strategy.rollingUpdate." + field),
                         get(after, "spec.rollout.strategy.rollingUpdate." + field))
                same(label + " deletion order", get(before, "spec.strategy.rollingUpdate.deletePolicy"),
                     get(after, "spec.deletion.order"))
            for field in ("nodeDrainTimeout", "nodeVolumeDetachTimeout", "nodeDeletionTimeout"):
                same(label + " " + field, duration_seconds(old_machine.get(field)),
                     get(new_machine, "deletion." + field + "Seconds"))
        if key[0] == "MachineHealthCheck":
            for field, target in (("maxUnhealthy", "unhealthyLessThanOrEqualTo"),
                                  ("unhealthyRange", "unhealthyInRange")):
                same(label + " " + field, get(before, "spec." + field),
                     get(after, "spec.remediation.triggerIf." + target))
            same(label + " node startup timeout", duration_seconds(get(before, "spec.nodeStartupTimeout")),
                 get(after, "spec.checks.nodeStartupTimeoutSeconds"))
            same(label + " unhealthy conditions",
                 [(c["type"], c["status"], duration_seconds(c.get("timeout")))
                  for c in get(before, "spec.unhealthyConditions", [])],
                 [(c["type"], c["status"], c.get("timeoutSeconds"))
                  for c in get(after, "spec.checks.unhealthyNodeConditions", [])])
        if key[0] in {"KubeadmControlPlane", "KubeadmConfigTemplate"}:
            left, right = bootstrap_spec(before), bootstrap_spec(after)
            # Compare complete contents of files and commands, not just paths.
            same(label + " files", with_defaults(left.get("files"), {"append": False, "content": ""}),
                 with_defaults(right.get("files"), {"append": False, "content": ""}))
            for field in ("preKubeadmCommands", "postKubeadmCommands", "bootCommands",
                          "users", "mounts", "diskSetup", "format", "verbosity", "ntp"):
                same(label + " " + field, left.get(field), right.get(field))
            for component in ("apiServer", "controllerManager", "scheduler"):
                path = "clusterConfiguration." + component + ".extraVolumes"
                same(label + " " + path, with_defaults(get(left, path), {"readOnly": False}),
                     with_defaults(get(right, path), {"readOnly": False}))
            for component in ("apiServer", "controllerManager", "scheduler", "etcd.local"):
                path = "clusterConfiguration." + component + ".extraEnvs"
                # KCP normalizes empty extraEnvs to nil before comparing configs.
                same(label + " " + path, get(left, path) or [], get(right, path) or [])
            for endpoint in ("initConfiguration.localAPIEndpoint",
                             "joinConfiguration.controlPlane.localAPIEndpoint"):
                for field, fallback in (("bindPort", 0), ("advertiseAddress", "")):
                    same(label + " " + endpoint + "." + field,
                         get(left, endpoint + "." + field, fallback),
                         get(right, endpoint + "." + field, fallback))
            same(label + " join controlPlane presence",
                 get(left, "joinConfiguration.controlPlane") is not None,
                 get(right, "joinConfiguration.controlPlane") is not None)
            for field in ("additionalConfig", "strict"):
                fallback = False if field == "strict" else ""
                path = "ignition.containerLinuxConfig." + field
                same(label + " " + path, get(left, path, fallback), get(right, path, fallback))
            same(label + " discovery timeout",
                 duration_seconds(get(left, "joinConfiguration.discovery.timeout")),
                 get(right, "joinConfiguration.timeouts.tlsBootstrapSeconds"))
            same(label + " discovery file", get(left, "joinConfiguration.discovery.file"),
                 get(right, "joinConfiguration.discovery.file"))
            for path in ARG_PATHS:
                same(label + " " + path, args_in_order(get(left, path)), args_in_order(get(right, path)))
            for phase in ("initConfiguration", "joinConfiguration"):
                left_node = get(left, phase + ".nodeRegistration", {})
                right_node = get(right, phase + ".nodeRegistration", {})
                same(label + " " + phase + " nodeRegistration",
                     {k: v for k, v in left_node.items() if k != "kubeletExtraArgs"},
                     {k: v for k, v in right_node.items() if k != "kubeletExtraArgs"})
        if key[0] == "OpenStackMachineTemplate":
            left, right = get(before, "spec.template.spec"), get(after, "spec.template.spec")
            same(label + " flavor", left.get("flavor"), get(right, "flavor.filter.name"))
            # An omitted identityRef.type defaults to Secret.
            li, ri = copy.copy(left.get("identityRef")), copy.copy(right.get("identityRef"))
            if li is not None:
                li.setdefault("type", "Secret")
            if ri is not None:
                ri.setdefault("type", "Secret")
            same(label + " identityRef", li, ri)
            for field in ("image", "sshKeyName", "rootVolume", "additionalBlockDevices",
                          "serverGroup", "securityGroups", "configDrive", "trunk"):
                same(label + " " + field, left.get(field), right.get(field))
        if key[0] == "OpenStackCluster":
            left, right = before["spec"], after["spec"]
            same(label + " enableExternalNetwork", not left.get("disableExternalNetwork", False),
                 right.get("enableExternalNetwork", True))
            api = right.get("apiServer", {})
            same(label + " floating IP enabled", not left.get("disableAPIServerFloatingIP", False),
                 api.get("enableFloatingIP", True))
            for source, target in (("apiServerPort", "port"), ("apiServerFixedIP", "fixedIP"),
                                   ("apiServerFloatingIP", "floatingIP"),
                                   ("apiServerLoadBalancer", "managedLoadBalancer")):
                same(label + " " + source, left.get(source), api.get(target))
            for field in ("network", "subnets", "managedSubnets", "managedSecurityGroups",
                          "externalNetwork", "controlPlaneOmitAvailabilityZone",
                          "controlPlaneAvailabilityZones"):
                same(label + " " + field, left.get(field), right.get(field))
    return errors


def partial_cases():
    return {
        "legacy-args-oidc": {
            "oidc": {"issuerUrl": "https://issuer.example.test", "clientId": "migration-client"},
            "controlPlane": {"kubeadmConfigSpec": {
                "clusterConfiguration": {
                    "apiServer": {"extraArgs": {"oidc-client-id": "explicit-client", "audit-log-maxage": "0"}},
                    "controllerManager": {"extraArgs": {"bind-address": "127.0.0.1", "v": "4"}},
                    "scheduler": {"extraArgs": {"bind-address": "127.0.0.2", "v": "5"}},
                    "etcd": {"local": {"extraArgs": {"heartbeat-interval": "750"}}}},
                "initConfiguration": {"nodeRegistration": {"kubeletExtraArgs": {"register-with-taints": "", "v": "3"}}},
                "joinConfiguration": {"nodeRegistration": {"kubeletExtraArgs": {"v": "2"}}}}},
            "nodeGroupDefaults": {"kubeadmConfigSpec": {"joinConfiguration": {
                "nodeRegistration": {"kubeletExtraArgs": {"v": "1", "register-with-taints": ""}}}}}},
        "false-zero": {
            "apiServer": {"associateFloatingIP": False, "enableLoadBalancer": False,
                          "fixedIP": "10.0.0.10"},
            "clusterNetworking": {"disableExternalNetwork": True, "allowAllInClusterTraffic": False},
            "controlPlane": {"machineConfigDrive": False, "nodeDrainTimeout": "0s",
                             "nodeVolumeDetachTimeout": "0s", "nodeDeletionTimeout": "0s",
                             "healthCheck": {"spec": {"maxUnhealthy": 0, "nodeStartupTimeout": "0s"}}},
            "nodeGroupDefaults": {"machineConfigDrive": False, "nodeDrainTimeout": "0s",
                                  "nodeVolumeDetachTimeout": "0s", "nodeDeletionTimeout": "0s",
                                  "healthCheck": {"spec": {"maxUnhealthy": 0, "nodeStartupTimeout": "0s"}}}},
        "group-isolation": {
            "nodeGroupDefaults": {"kubeadmConfigSpec": {"joinConfiguration": {
                "nodeRegistration": {"kubeletExtraArgs": {"v": "1"}}}}},
            "nodeGroups": [
                {"name": "group-1", "machineFlavor": "vm.small", "machineCount": 1,
                 "kubeadmConfigSpec": {"joinConfiguration": {"nodeRegistration": {
                     "kubeletExtraArgs": {"v": "8", "max-pods": "120"}}}}},
                {"name": "group-2", "machineFlavor": "vm.large", "machineCount": 1}]},
        "duration-and-certificates": {
            "controlPlane": {"nodeDrainTimeout": "2m30.5s", "certificatesExpiryDays": 0,
                             "healthCheck": {"spec": {"nodeStartupTimeout": "1h2m3s"}}},
            "nodeGroupDefaults": {"nodeDrainTimeout": "2m30.5s",
                                  "healthCheck": {"spec": {"nodeStartupTimeout": "1h2m3s"}}}},
        "bootstrap-optional": {
            "osDistro": "flatcar",
            "machineImage": "flatcar-kube-v{{ .Values.kubernetesVersion }}",
            "controlPlane": {"kubeadmConfigSpec": {
                "files": [{"path": "/etc/test-empty", "content": "", "append": False}],
                "ignition": {"containerLinuxConfig": {"strict": False}},
                "initConfiguration": {"nodeRegistration": {"taints": []}},
                "joinConfiguration": {"discovery": {"timeout": "45s", "file": None},
                                      "nodeRegistration": {"taints": []}},
                "clusterConfiguration": {"apiServer": {"extraVolumes": [{
                    "name": "optional-volume", "hostPath": "/etc/test-volume",
                    "mountPath": "/etc/test-volume", "readOnly": False, "pathType": "Directory"}]}}}},
            "nodeGroupDefaults": {"kubeadmConfigSpec": {
                "files": [{"path": "/etc/test-empty", "content": "", "append": False}],
                "ignition": {"containerLinuxConfig": {"strict": False}},
                "joinConfiguration": {"discovery": {"timeout": "45s", "file": None},
                                      "nodeRegistration": {"taints": []}}}}},
        "bootstrap-defaults": {
            "controlPlane": {"kubeadmConfigSpec": {
                "clusterConfiguration": {
                    "apiServer": {"extraEnvs": []},
                    "controllerManager": {"extraEnvs": []},
                    "scheduler": {"extraEnvs": []},
                    "etcd": {"local": {"extraEnvs": []}}},
                "initConfiguration": {"localAPIEndpoint": {"bindPort": 0, "advertiseAddress": ""}},
                "joinConfiguration": {"controlPlane": {
                    "localAPIEndpoint": {"bindPort": 0, "advertiseAddress": ""}}}}}},
    }


def template_slots(resources):
    result = {}
    for (kind, name), resource in resources.items():
        if kind not in TEMPLATES:
            continue
        labels = resource["metadata"]["labels"]
        group = next((v for k, v in labels.items() if k.endswith("/node-group")), "control-plane")
        result[(kind, group)] = {"name": name, "checksum": checksums(resource)}
    return result


def check_real_changes(helm, working, fixtures, output):
    """Check that changed settings still produce new template names and hashes."""
    baseline_values = {"nodeGroups": [
        {"name": "group-1", "machineFlavor": "vm.small", "machineCount": 1},
        {"name": "group-2", "machineFlavor": "vm.large", "machineCount": 1}]}
    cases = []
    cp_flavor = copy.deepcopy(baseline_values)
    cp_flavor["controlPlane"] = {"machineFlavor": "vm.changed"}
    cases.append(("control-plane-flavor", cp_flavor, ("OpenStackMachineTemplate", "control-plane")))
    worker_flavor = copy.deepcopy(baseline_values)
    worker_flavor["nodeGroups"][0]["machineFlavor"] = "vm.changed"
    cases.append(("worker-flavor", worker_flavor, ("OpenStackMachineTemplate", "group-1")))
    worker_bootstrap = copy.deepcopy(baseline_values)
    worker_bootstrap["nodeGroups"][0]["kubeadmConfigSpec"] = {
        "joinConfiguration": {"nodeRegistration": {"kubeletExtraArgs": {"v": "9"}}}}
    cases.append(("worker-bootstrap", worker_bootstrap, ("KubeadmConfigTemplate", "group-1")))
    base_path = output / "mutation.baseline.values.yaml"
    base_path.write_text(yaml.safe_dump(baseline_values))
    before = render(helm, working, [fixtures / "values_base.yaml", base_path],
                    output / "mutation.baseline.yaml")
    old_slots = template_slots(before)
    results = []
    for case, values, expected in cases:
        values_path = output / ("mutation." + case + ".values.yaml")
        values_path.write_text(yaml.safe_dump(values))
        path = output / ("mutation." + case + ".yaml")
        after = render(helm, working, [fixtures / "values_base.yaml", values_path], path)
        new_slots = template_slots(after)
        changed_names = sorted(key for key in old_slots if key in new_slots and
                               old_slots[key]["name"] != new_slots[key]["name"])
        changed_checksums = sorted(key for key in old_slots if key in new_slots and
                                   old_slots[key]["checksum"] != new_slots[key]["checksum"])
        dangling = [ref for resource in after.values() if resource["kind"] in KINDS
                    for ref in refs(resource["spec"])
                    if ref[1] in TEMPLATES and (ref[1], ref[2]) not in after]
        result = {"name": case, "changed_names": changed_names,
                  "changed_checksums": changed_checksums, "dangling_references": dangling}
        result["pass"] = (old_slots.keys() == new_slots.keys() and changed_names == [expected]
                          and changed_checksums == [expected] and not dangling)
        print(("PASS " if result["pass"] else "FAIL ") + "mutation." + case, flush=True)
        results.append(result)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--helm", default="helm")
    parser.add_argument("--baseline-ref", default="390e8a99", help="Pre-migration main commit")
    parser.add_argument("--old-tag", action="append", help="Repeat to override defaults 0.28.1,0.29.0")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    args.repo = args.repo.resolve()
    args.old_tag = args.old_tag or ["0.28.1", "0.29.0"]
    output = (args.output_dir or args.repo / ".artifacts/capo-validation" /
              ("v1beta2-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))).resolve()
    output.mkdir(parents=True, exist_ok=False)
    working = output / "working"
    shutil.copytree(args.repo / "charts", working / "charts",
                    ignore=shutil.ignore_patterns("__snapshot__", "*.tgz"))
    prepare(args.helm, working, output / "working.dependencies.log")
    current_defaults = (working / "charts/openstack-cluster/values.yaml").read_bytes()
    fixtures = args.repo / "charts/openstack-cluster/tests"
    cases = {"base": [fixtures / "values_base.yaml"],
             "full": [fixtures / "values_base.yaml", fixtures / "values_full.yaml"],
             "ovn": [fixtures / "values_base.yaml", fixtures / "values_ovn.yaml"]}
    for name, values in partial_cases().items():
        path = output / (name + ".values.yaml")
        path.write_text(yaml.safe_dump(values, sort_keys=False))
        cases[name] = [fixtures / "values_base.yaml", path]
    report = {"baseline_refs": {}, "cases": [], "real_changes": [],
              "limitations": ["No schema validation. Run the separate kubeconform checks.",
                              "Does not test API-server defaulting, conversion, admission, or live rollouts.",
                              "Compares selected settings. Does not reproduce the full upstream conversion."]}
    report["helm_version"] = run([args.helm, "version", "--short"]).stdout.decode().strip()
    report["python_version"] = sys.version
    report["pyyaml_version"] = yaml.__version__
    report["working_git_head"] = run(["git", "-C", args.repo, "rev-parse", "HEAD"]).stdout.decode().strip()
    report["working_git_diff"] = run(["git", "-C", args.repo, "diff", "--stat"]).stdout.decode()
    for label, ref in [("main", args.baseline_ref)] + [("release-" + tag, tag) for tag in args.old_tag]:
        baseline = output / label
        report["baseline_refs"][label] = archive(args.repo, ref, baseline)
        prepare(args.helm, baseline, output / (label + ".dependencies.log"))
        old_defaults = (baseline / "charts/openstack-cluster/values.yaml").read_bytes()
        for case, overrides in cases.items():
            # Use historical defaults for base/full/ovn.
            # Test partial overrides with current defaults in both chart versions.
            defaults = current_defaults if case not in {"base", "full", "ovn"} else old_defaults
            for directory in (baseline, working):
                (directory / "charts/openstack-cluster/values.yaml").write_bytes(defaults)
            name = label + "." + case
            result = {"name": name}
            try:
                old = render(args.helm, baseline, overrides, output / (name + ".old.yaml"))
                new_path = output / (name + ".new.yaml")
                new = render(args.helm, working, overrides, new_path)
                result["differences"] = compare(old, new)
                result["pass"] = not result["differences"]
            except (AssertionError, subprocess.CalledProcessError, ValueError, KeyError) as error:
                result.update({"pass": False, "error": str(error)})
            report["cases"].append(result)
            print(("PASS " if result["pass"] else "FAIL ") + name, flush=True)
    (working / "charts/openstack-cluster/values.yaml").write_bytes(current_defaults)
    report["real_changes"] = check_real_changes(args.helm, working, fixtures, output)
    report["pass"] = all(case["pass"] for case in report["cases"]) and all(
        change["pass"] for change in report["real_changes"])
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("Report: " + str(output / "report.json"))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
