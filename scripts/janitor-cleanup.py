#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openstacksdk==4.13.0"]
# ///
"""Check real workload resources across deletion of a disposable CAPI cluster."""

import argparse
import json
import logging
import os
from pathlib import Path
import subprocess
import sys
import time
from uuid import UUID


WORKLOAD_NAMESPACE = "janitor-cleanup-test"
RESOURCE_NAME = "janitor-cleanup"
LB_ID_ANNOTATION = "loadbalancer.openstack.org/load-balancer-id"
VOLUME_POLICY_ANNOTATION = "janitor.capi.stackhpc.com/volumes-policy"


class CleanupError(RuntimeError):
    """A test failure that is safe to include in CI logs."""


def status_code(error):
    status = getattr(error, "status_code", None)
    if status is None:
        status = getattr(error, "http_status", None)
    return status if isinstance(status, int) else None


def error_summary(error):
    status = status_code(error)
    return type(error).__name__ + (f" (HTTP {status})" if status else "")


def get_resource(getter, resource_id):
    """Only an explicit HTTP 404 proves that this exact resource is absent."""
    try:
        resource = getter(resource_id)
    except Exception as error:
        if status_code(error) == 404:
            return None
        raise CleanupError(f"Get resource {resource_id}: {error_summary(error)}") from None
    if resource is None:
        raise CleanupError(f"Get resource {resource_id} returned no resource without HTTP 404")
    return resource


def write_state(state, path):
    Path(path).write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def checked_id(value):
    try:
        if not isinstance(value, str) or str(UUID(value)) != value.lower():
            raise ValueError
    except (ValueError, AttributeError):
        raise CleanupError("Expected an OpenStack resource UUID") from None
    return value


def record_id(state, key, value, state_path):
    if not value:
        return
    checked_id(value)
    if state.get(key) and state[key] != value:
        raise CleanupError(f"Recorded {key} changed during preparation")
    state[key] = value
    write_state(state, state_path)


class Deadline:
    def __init__(self, seconds):
        self.end = time.monotonic() + seconds

    def remaining(self):
        remaining = self.end - time.monotonic()
        if remaining <= 0:
            raise CleanupError("Timed out waiting for Janitor cleanup test resources")
        return remaining

    def pause(self):
        time.sleep(min(5, self.remaining()))


def kubectl(arguments, deadline, kubeconfig=None, manifest=None):
    timeout = min(30, deadline.remaining())
    command = ["kubectl", f"--request-timeout={timeout:.3f}s"]
    if kubeconfig:
        command.extend(["--kubeconfig", kubeconfig])
    command.extend(arguments)
    operation = " ".join(arguments[:2])
    try:
        result = subprocess.run(
            command, input=json.dumps(manifest) if manifest else None,
            capture_output=True, text=True, timeout=timeout, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CleanupError(f"kubectl {operation}: {type(error).__name__}") from None
    if result.returncode:
        # kubectl stderr and API response bodies can contain sensitive data.
        raise CleanupError(f"kubectl {operation} failed (exit {result.returncode})")
    if "-o=json" in arguments:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            raise CleanupError("kubectl returned invalid JSON") from None
    return None


def cloud_connection(deadline):
    for variable in ("OS_CLOUD", "OS_CLIENT_CONFIG_FILE"):
        if not os.environ.get(variable):
            raise CleanupError(f"{variable} must identify the CI observer credentials")
    import openstack

    for name in ("openstack", "keystoneauth", "urllib3"):
        logging.getLogger(name).setLevel(logging.CRITICAL)
    try:
        connection = openstack.connect(
            cloud=os.environ["OS_CLOUD"], api_timeout=min(30, deadline.remaining()),
        )
        connection.authorize()
    except Exception as error:
        raise CleanupError(f"Authenticate CI observer: {error_summary(error)}") from None
    return connection


def fixture_manifest():
    labels = {"app": RESOURCE_NAME}
    metadata = {"name": RESOURCE_NAME, "namespace": WORKLOAD_NAMESPACE}
    return {
        "apiVersion": "v1", "kind": "List", "items": [
            {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": WORKLOAD_NAMESPACE}},
            {
                "apiVersion": "v1", "kind": "PersistentVolumeClaim", "metadata": metadata,
                "spec": {
                    "accessModes": ["ReadWriteOnce"], "storageClassName": "csi-cinder",
                    "resources": {"requests": {"storage": "1Gi"}},
                },
            },
            {
                "apiVersion": "v1", "kind": "Pod", "metadata": {**metadata, "labels": labels},
                "spec": {
                    "containers": [{
                        "name": "web", "image": "registry.k8s.io/e2e-test-images/agnhost:2.53",
                        "command": ["/agnhost", "netexec", "--http-port=8080"],
                        "ports": [{"containerPort": 8080}],
                        "readinessProbe": {"httpGet": {"path": "/hostname", "port": 8080}},
                        "volumeMounts": [{"name": "data", "mountPath": "/data"}],
                    }],
                    "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": RESOURCE_NAME}}],
                },
            },
            {
                "apiVersion": "v1", "kind": "Service", "metadata": metadata,
                "spec": {
                    "type": "LoadBalancer", "selector": labels,
                    "ports": [{"name": "http", "port": 80, "targetPort": 8080}],
                },
            },
        ],
    }


def prepare(args, connection, state, deadline):
    cluster = kubectl(
        ["get", "openstackcluster", args.cluster_name, "-n", args.namespace, "-o=json"], deadline,
    )
    if cluster["metadata"].get("deletionTimestamp"):
        raise CleanupError("The test OpenStackCluster is already deleting")
    state["cluster_uid"] = cluster["metadata"]["uid"]
    write_state(state, args.state_file)
    kubectl([
        "annotate", "openstackcluster", args.cluster_name, "-n", args.namespace,
        f"{VOLUME_POLICY_ANNOTATION}=delete", "--overwrite",
    ], deadline)
    kubectl(["create", "-f", "-"], deadline, args.workload_kubeconfig, fixture_manifest())

    while True:
        service = kubectl(
            ["get", "service", RESOURCE_NAME, "-n", WORKLOAD_NAMESPACE, "-o=json"],
            deadline, args.workload_kubeconfig,
        )
        record_id(state, "load_balancer_id", service["metadata"].get("annotations", {}).get(LB_ID_ANNOTATION), args.state_file)
        claim = kubectl(
            ["get", "pvc", RESOURCE_NAME, "-n", WORKLOAD_NAMESPACE, "-o=json"],
            deadline, args.workload_kubeconfig,
        )
        pv_name = claim.get("spec", {}).get("volumeName")
        if pv_name:
            volume = kubectl(["get", "pv", pv_name, "-o=json"], deadline, args.workload_kubeconfig)
            csi = volume["spec"].get("csi", {})
            if csi.get("driver") != "cinder.csi.openstack.org":
                raise CleanupError("The test PVC was not provisioned by Cinder CSI")
            record_id(state, "volume_id", csi.get("volumeHandle"), args.state_file)
            if volume["spec"].get("persistentVolumeReclaimPolicy") != "Delete":
                raise CleanupError("The test PV must use the Delete reclaim policy")
        pod = kubectl(
            ["get", "pod", RESOURCE_NAME, "-n", WORKLOAD_NAMESPACE, "-o=json"],
            deadline, args.workload_kubeconfig,
        )
        pod_ready = any(
            condition.get("type") == "Ready" and condition.get("status") == "True"
            for condition in pod.get("status", {}).get("conditions", [])
        )
        if (state.get("load_balancer_id") and state.get("volume_id") and pod_ready
                and claim.get("status", {}).get("phase") == "Bound"
                and service.get("status", {}).get("loadBalancer", {}).get("ingress")):
            break
        deadline.pause()

    for key, getter in resource_getters(connection):
        connection.session.timeout = min(30, deadline.remaining())
        if get_resource(getter, state[key]) is None:
            raise CleanupError(f"Recorded {key} is absent before cluster deletion")
    state["prepared"] = True
    write_state(state, args.state_file)
    print("Confirmed the workload load balancer and Cinder volume exist")


def resource_getters(connection):
    return (
        ("load_balancer_id", connection.load_balancer.get_load_balancer),
        ("volume_id", connection.block_storage.get_volume),
    )


def verify(connection, state, state_path, timeout):
    if state.get("prepared") is not True:
        raise CleanupError("Preparation did not confirm both OpenStack resources")
    for key in ("load_balancer_id", "volume_id"):
        checked_id(state.get(key))
    deadline = Deadline(timeout)
    while True:
        remaining = {}
        for key, getter in resource_getters(connection):
            connection.session.timeout = min(30, deadline.remaining())
            if get_resource(getter, state[key]) is not None:
                remaining[key] = state[key]
        state["remaining"] = remaining
        state["verified"] = not remaining
        write_state(state, state_path)
        if state["verified"]:
            print("Confirmed HTTP 404 for the recorded load balancer and Cinder volume")
            return
        deadline.pause()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="phase", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--cluster-name", required=True)
    prepare_parser.add_argument("--namespace", default="default", help="Management OpenStackCluster namespace")
    prepare_parser.add_argument("--workload-kubeconfig", required=True)
    verify_parser = commands.add_parser("verify")
    for command in (prepare_parser, verify_parser):
        command.add_argument("--state-file", type=Path, required=True)
        command.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args(argv)
    state = None
    try:
        if args.timeout <= 0:
            raise CleanupError("Timeout must be positive")
        deadline = Deadline(args.timeout)
        if args.phase == "prepare":
            if args.state_file.exists():
                raise CleanupError("The state file already exists. Use a fresh disposable test cluster")
            state = {
                "cluster_name": args.cluster_name, "namespace": args.namespace,
                "workload_namespace": WORKLOAD_NAMESPACE, "prepared": False, "verified": False,
            }
            write_state(state, args.state_file)
        else:
            state = json.loads(args.state_file.read_text(encoding="utf-8"))
        connection = cloud_connection(deadline)
        if args.phase == "prepare":
            prepare(args, connection, state, deadline)
        else:
            verify(connection, state, args.state_file, deadline.remaining())
    except Exception as error:
        message = str(error) if isinstance(error, CleanupError) else error_summary(error)
        if isinstance(state, dict):
            state["error"] = message
            write_state(state, args.state_file)
        print(f"Janitor cleanup check failed: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
