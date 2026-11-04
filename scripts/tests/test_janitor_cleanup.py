"""Offline tests for the Janitor cleanup check."""

import importlib.util
import itertools
import json
from pathlib import Path
import sys
import tempfile
import traceback
from types import SimpleNamespace
import unittest
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "janitor-cleanup.py"
SPEC = importlib.util.spec_from_file_location("janitor_cleanup", SCRIPT_PATH)
cleanup = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = cleanup
# Importing and testing the helpers must not require the cloud SDK.
with mock.patch.dict(sys.modules, {"openstack": None}):
    SPEC.loader.exec_module(cleanup)


LB_ID = "11111111-1111-4111-8111-111111111111"
VOLUME_ID = "22222222-2222-4222-8222-222222222222"
OTHER_ID = "33333333-3333-4333-8333-333333333333"
RAW_BODY = "sensitive-cloud-response-and-credential-marker"


class HTTPFailure(Exception):
    def __init__(self, status, attribute="status_code"):
        super().__init__(RAW_BODY)
        self.status_code = None
        setattr(self, attribute, status)


class GetResourceTests(unittest.TestCase):
    def test_only_explicit_http_404_means_absent(self):
        for attribute in ("status_code", "http_status"):
            with self.subTest(attribute=attribute):
                getter = mock.Mock(side_effect=HTTPFailure(404, attribute))

                self.assertIsNone(cleanup.get_resource(getter, LB_ID))
                getter.assert_called_once_with(LB_ID)

    def test_http_errors_fail_without_exposing_the_response(self):
        for attribute in ("status_code", "http_status"):
            for status in (401, 403, 500):
                with self.subTest(attribute=attribute, status=status):
                    getter = mock.Mock(side_effect=HTTPFailure(status, attribute))

                    try:
                        cleanup.get_resource(getter, LB_ID)
                    except cleanup.CleanupError as error:
                        self.assertNotIn(RAW_BODY, str(error))
                        formatted = traceback.format_exception(type(error), error, error.__traceback__)
                        self.assertNotIn(RAW_BODY, "".join(formatted))
                    else:
                        self.fail(f"HTTP {status} was accepted as absence")
                    getter.assert_called_once_with(LB_ID)

    def test_transport_errors_are_sanitized_failures(self):
        for error in (TimeoutError(RAW_BODY), ConnectionError(RAW_BODY)):
            with self.subTest(error=type(error).__name__):
                getter = mock.Mock(side_effect=error)

                with self.assertRaises(cleanup.CleanupError) as raised:
                    cleanup.get_resource(getter, LB_ID)

                self.assertNotIn(RAW_BODY, str(raised.exception))
                getter.assert_called_once_with(LB_ID)

    def test_none_without_http_404_is_not_absence(self):
        getter = mock.Mock(return_value=None)

        with self.assertRaises(cleanup.CleanupError):
            cleanup.get_resource(getter, LB_ID)

        getter.assert_called_once_with(LB_ID)


class StateFileTestCase(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.state_path = Path(directory.name) / "state.json"

    def read_state(self):
        return json.loads(self.state_path.read_text(encoding="utf-8"))

    def write_state(self, state):
        self.state_path.write_text(json.dumps(state), encoding="utf-8")


class StateTests(StateFileTestCase):
    def test_records_partial_ids_immediately_before_later_failure(self):
        state = {"prepared": False}

        cleanup.record_id(state, "load_balancer_id", LB_ID, self.state_path)
        self.assertEqual(self.read_state(), {"prepared": False, "load_balancer_id": LB_ID})

        with self.assertRaises(cleanup.CleanupError):
            cleanup.record_id(state, "volume_id", "not-a-resource-uuid", self.state_path)

        self.assertEqual(self.read_state(), {"prepared": False, "load_balancer_id": LB_ID})
        self.assertNotIn("volume_id", state)

    def test_changed_id_does_not_replace_the_recorded_target(self):
        state = {"prepared": False}
        cleanup.record_id(state, "load_balancer_id", LB_ID, self.state_path)
        recorded = dict(state)

        with self.assertRaises(cleanup.CleanupError):
            cleanup.record_id(state, "load_balancer_id", OTHER_ID, self.state_path)

        self.assertEqual(state, recorded)
        self.assertEqual(self.read_state(), recorded)

    def test_nonempty_invalid_id_is_not_persisted(self):
        for value in ("not-a-uuid", RAW_BODY, 42, [LB_ID]):
            with self.subTest(value=value):
                state = {"prepared": False}
                self.write_state(state)

                with self.assertRaises(cleanup.CleanupError):
                    cleanup.record_id(state, "volume_id", value, self.state_path)

                self.assertEqual(self.read_state(), {"prepared": False})
                self.assertNotIn("volume_id", state)


class PrepareTests(StateFileTestCase):
    def test_preparation_records_service_and_pv_ids_before_cluster_deletion(self):
        args = SimpleNamespace(
            cluster_name="test-cluster", namespace="default",
            workload_kubeconfig="workload-kubeconfig", state_file=self.state_path,
        )
        state = {"prepared": False, "verified": False}
        responses = [
            {"metadata": {"uid": "cluster-uid"}},
            None,
            None,
            {
                "metadata": {"annotations": {cleanup.LB_ID_ANNOTATION: LB_ID}},
                "status": {"loadBalancer": {"ingress": [{"ip": "192.0.2.10"}]}},
            },
            {"spec": {"volumeName": "test-pv"}, "status": {"phase": "Bound"}},
            {"spec": {
                "csi": {"driver": "cinder.csi.openstack.org", "volumeHandle": VOLUME_ID},
                "persistentVolumeReclaimPolicy": "Delete",
            }},
            {"status": {"conditions": [{"type": "Ready", "status": "True"}]}},
        ]
        connection = SimpleNamespace(
            load_balancer=SimpleNamespace(get_load_balancer=mock.Mock(return_value=object())),
            block_storage=SimpleNamespace(get_volume=mock.Mock(return_value=object())),
            session=SimpleNamespace(timeout=None),
        )
        with mock.patch.object(cleanup, "kubectl", side_effect=responses) as kubectl:
            cleanup.prepare(args, connection, state, cleanup.Deadline(30))

        connection.load_balancer.get_load_balancer.assert_called_once_with(LB_ID)
        connection.block_storage.get_volume.assert_called_once_with(VOLUME_ID)
        self.assertIs(self.read_state()["prepared"], True)
        self.assertEqual(self.read_state()["load_balancer_id"], LB_ID)
        self.assertEqual(self.read_state()["volume_id"], VOLUME_ID)
        calls = kubectl.call_args_list
        self.assertIn(f"{cleanup.VOLUME_POLICY_ANNOTATION}=delete", calls[1].args[0])
        self.assertEqual(calls[2].args[0], ["create", "-f", "-"])
        for call in calls[2:]:
            self.assertEqual(call.args[2], args.workload_kubeconfig)
        self.assertFalse(any(call.args[0][0] == "delete" for call in calls))
        fixture = calls[2].args[3]
        items = {item["kind"]: item for item in fixture["items"]}
        self.assertEqual(items["Service"]["spec"]["type"], "LoadBalancer")
        self.assertEqual(
            items["Pod"]["spec"]["volumes"][0]["persistentVolumeClaim"]["claimName"],
            items["PersistentVolumeClaim"]["metadata"]["name"],
        )


class VerifyTests(StateFileTestCase):
    def setUp(self):
        super().setUp()
        self.state = {
            "prepared": True,
            "verified": False,
            "load_balancer_id": LB_ID,
            "volume_id": VOLUME_ID,
        }
        self.write_state(self.state)
        self.lb_getter = mock.Mock()
        self.volume_getter = mock.Mock()
        self.connection = SimpleNamespace(
            load_balancer=SimpleNamespace(get_load_balancer=self.lb_getter),
            block_storage=SimpleNamespace(get_volume=self.volume_getter),
            session=SimpleNamespace(timeout=None),
        )
        # Advance time on every check without waiting.
        self.clock = mock.patch.object(cleanup.time, "monotonic", side_effect=itertools.count())
        self.clock.start()
        self.addCleanup(self.clock.stop)
        self.sleep = mock.patch.object(cleanup.time, "sleep", return_value=None)
        self.sleep_mock = self.sleep.start()
        self.addCleanup(self.sleep.stop)

    def assert_exact_ids(self):
        self.assertTrue(self.lb_getter.called)
        self.assertTrue(self.volume_getter.called)
        self.assertTrue(all(call == mock.call(LB_ID) for call in self.lb_getter.call_args_list))
        self.assertTrue(all(call == mock.call(VOLUME_ID) for call in self.volume_getter.call_args_list))

    def test_polls_the_recorded_ids_until_both_are_http_404(self):
        self.lb_getter.side_effect = [SimpleNamespace(id=LB_ID), HTTPFailure(404)]
        self.volume_getter.side_effect = HTTPFailure(404, "http_status")

        cleanup.verify(self.connection, self.state, self.state_path, timeout=30)

        self.assert_exact_ids()
        self.assertGreaterEqual(self.lb_getter.call_count, 2)
        self.sleep_mock.assert_called()
        self.assertIs(self.state["verified"], True)
        self.assertIs(self.read_state()["verified"], True)
        self.assertEqual(self.read_state()["load_balancer_id"], LB_ID)
        self.assertEqual(self.read_state()["volume_id"], VOLUME_ID)

    def test_one_remaining_resource_times_out_without_verified_success(self):
        for present_key in ("load_balancer_id", "volume_id"):
            with self.subTest(present_key=present_key):
                self.state["verified"] = False
                self.write_state(self.state)
                for key, getter in (
                    ("load_balancer_id", self.lb_getter),
                    ("volume_id", self.volume_getter),
                ):
                    getter.reset_mock()
                    getter.side_effect = None if key == present_key else HTTPFailure(404)
                    getter.return_value = SimpleNamespace(id=self.state[key])

                with self.assertRaises(cleanup.CleanupError):
                    cleanup.verify(self.connection, self.state, self.state_path, timeout=8)

                self.assert_exact_ids()
                self.assertIsNot(self.state.get("verified"), True)
                self.assertIsNot(self.read_state().get("verified"), True)

    def test_verification_rejects_an_unconfirmed_preparation(self):
        for prepared in (None, False, 1, "true"):
            with self.subTest(prepared=prepared):
                state = {**self.state, "prepared": prepared}

                with self.assertRaises(cleanup.CleanupError):
                    cleanup.verify(self.connection, state, self.state_path, timeout=30)

                self.lb_getter.assert_not_called()
                self.volume_getter.assert_not_called()

    def test_verification_rejects_missing_or_invalid_recorded_ids(self):
        for key in ("load_balancer_id", "volume_id"):
            for value in (None, "", "not-a-uuid"):
                with self.subTest(key=key, value=value):
                    state = {**self.state, key: value}

                    with self.assertRaises(cleanup.CleanupError):
                        cleanup.verify(self.connection, state, self.state_path, timeout=30)

                    self.lb_getter.assert_not_called()
                    self.volume_getter.assert_not_called()

    def test_verification_does_not_accept_cloud_errors_as_cleanup(self):
        self.lb_getter.side_effect = HTTPFailure(404)
        self.volume_getter.side_effect = HTTPFailure(403)

        with self.assertRaises(cleanup.CleanupError) as raised:
            cleanup.verify(self.connection, self.state, self.state_path, timeout=30)

        self.assert_exact_ids()
        self.assertNotIn(RAW_BODY, str(raised.exception))
        self.assertIsNot(self.state.get("verified"), True)
        self.assertIsNot(self.read_state().get("verified"), True)


if __name__ == "__main__":
    unittest.main()
