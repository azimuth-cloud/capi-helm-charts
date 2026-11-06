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
FIP_ID = "44444444-4444-4444-8444-444444444444"
VIP_PORT_ID = "55555555-5555-4555-8555-555555555555"
FIP_ADDRESS = "192.0.2.10"
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


class FindFloatingIPTests(unittest.TestCase):
    def setUp(self):
        self.floating_ip = SimpleNamespace(
            id=FIP_ID, port_id=VIP_PORT_ID, floating_ip_address=FIP_ADDRESS,
        )
        self.load_balancer = SimpleNamespace(id=LB_ID, vip_port_id=VIP_PORT_ID)
        self.connection = SimpleNamespace(
            load_balancer=SimpleNamespace(get_load_balancer=mock.Mock(return_value=self.load_balancer)),
            network=SimpleNamespace(ips=mock.Mock(return_value=[self.floating_ip])),
            session=SimpleNamespace(timeout=None),
        )

    def find(self):
        return cleanup.find_floating_ip(
            self.connection, LB_ID, [{"ip": FIP_ADDRESS}], cleanup.Deadline(30),
        )

    def test_finds_the_floating_ip_on_the_vip_port_with_the_service_address(self):
        self.assertIs(self.find(), self.floating_ip)

        self.connection.load_balancer.get_load_balancer.assert_called_once_with(LB_ID)
        self.connection.network.ips.assert_called_once_with(port_id=VIP_PORT_ID)

    def test_missing_or_unrelated_floating_ips_do_not_match(self):
        for candidates in (
            [],
            [SimpleNamespace(id=FIP_ID, port_id=OTHER_ID, floating_ip_address=FIP_ADDRESS)],
            [SimpleNamespace(id=FIP_ID, port_id=VIP_PORT_ID, floating_ip_address="192.0.2.11")],
        ):
            with self.subTest(candidates=candidates):
                self.connection.network.ips.return_value = candidates

                self.assertIsNone(self.find())

    def test_missing_vip_port_does_not_list_unrelated_floating_ips(self):
        self.load_balancer.vip_port_id = None

        with self.assertRaises(cleanup.CleanupError):
            self.find()

        self.connection.network.ips.assert_not_called()

    def test_multiple_matches_are_rejected(self):
        self.connection.network.ips.return_value = [
            self.floating_ip,
            SimpleNamespace(id=OTHER_ID, port_id=VIP_PORT_ID, floating_ip_address=FIP_ADDRESS),
        ]

        with self.assertRaises(cleanup.CleanupError):
            self.find()

    def test_errors_while_iterating_floating_ips_are_sanitized(self):
        def failed_listing(status):
            yield self.floating_ip
            raise HTTPFailure(status)

        for status in (401, 403, 404, 500):
            with self.subTest(status=status):
                self.connection.network.ips.return_value = failed_listing(status)

                with self.assertRaises(cleanup.CleanupError) as raised:
                    self.find()

                self.assertNotIn(RAW_BODY, str(raised.exception))


class PrepareTests(StateFileTestCase):
    def test_preparation_waits_for_the_floating_ip_and_records_all_ids(self):
        args = SimpleNamespace(
            cluster_name="test-cluster", namespace="default",
            workload_kubeconfig="workload-kubeconfig", state_file=self.state_path,
        )
        state = {"prepared": False, "verified": False}
        cluster_responses = [
            {"metadata": {"uid": "cluster-uid"}},
            None,
            None,
        ]
        workload_responses = [
            {
                "metadata": {"annotations": {cleanup.LB_ID_ANNOTATION: LB_ID}},
                "status": {"loadBalancer": {"ingress": [{"ip": FIP_ADDRESS}]}},
            },
            {"spec": {"volumeName": "test-pv"}, "status": {"phase": "Bound"}},
            {"spec": {
                "csi": {"driver": "cinder.csi.openstack.org", "volumeHandle": VOLUME_ID},
                "persistentVolumeReclaimPolicy": "Delete",
            }},
            {"status": {"conditions": [{"type": "Ready", "status": "True"}]}},
        ]
        floating_ip = SimpleNamespace(id=FIP_ID, port_id=VIP_PORT_ID, floating_ip_address=FIP_ADDRESS)
        connection = SimpleNamespace(
            load_balancer=SimpleNamespace(
                get_load_balancer=mock.Mock(return_value=SimpleNamespace(id=LB_ID, vip_port_id=VIP_PORT_ID)),
            ),
            network=SimpleNamespace(
                ips=mock.Mock(side_effect=[[], [floating_ip]]),
                get_ip=mock.Mock(return_value=floating_ip),
            ),
            block_storage=SimpleNamespace(get_volume=mock.Mock(return_value=object())),
            session=SimpleNamespace(timeout=None),
        )
        with (
            mock.patch.object(cleanup, "kubectl", side_effect=cluster_responses + workload_responses * 2) as kubectl,
            mock.patch.object(cleanup.time, "sleep") as sleep,
        ):
            cleanup.prepare(args, connection, state, cleanup.Deadline(30))

        self.assertTrue(all(call == mock.call(LB_ID) for call in connection.load_balancer.get_load_balancer.call_args_list))
        connection.network.get_ip.assert_called_once_with(FIP_ID)
        connection.block_storage.get_volume.assert_called_once_with(VOLUME_ID)
        sleep.assert_called_once()
        self.assertIs(self.read_state()["prepared"], True)
        self.assertEqual(self.read_state()["load_balancer_id"], LB_ID)
        self.assertEqual(self.read_state()["floating_ip_id"], FIP_ID)
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
            "floating_ip_id": FIP_ID,
            "volume_id": VOLUME_ID,
        }
        self.write_state(self.state)
        self.lb_getter = mock.Mock()
        self.fip_getter = mock.Mock()
        self.volume_getter = mock.Mock()
        self.getters = {
            "load_balancer_id": self.lb_getter,
            "floating_ip_id": self.fip_getter,
            "volume_id": self.volume_getter,
        }
        self.connection = SimpleNamespace(
            load_balancer=SimpleNamespace(get_load_balancer=self.lb_getter),
            network=SimpleNamespace(get_ip=self.fip_getter),
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
        for key, getter in self.getters.items():
            self.assertTrue(getter.called)
            self.assertTrue(all(call == mock.call(self.state[key]) for call in getter.call_args_list))

    def test_polls_the_recorded_ids_until_all_are_http_404(self):
        self.lb_getter.side_effect = [SimpleNamespace(id=LB_ID), HTTPFailure(404)]
        self.fip_getter.side_effect = [SimpleNamespace(id=FIP_ID, port_id=None), HTTPFailure(404)]
        self.volume_getter.side_effect = HTTPFailure(404, "http_status")

        cleanup.verify(self.connection, self.state, self.state_path, timeout=30)

        self.assert_exact_ids()
        self.assertGreaterEqual(self.lb_getter.call_count, 2)
        self.sleep_mock.assert_called()
        self.assertIs(self.state["verified"], True)
        self.assertIs(self.read_state()["verified"], True)
        self.assertEqual(self.read_state()["load_balancer_id"], LB_ID)
        self.assertEqual(self.read_state()["floating_ip_id"], FIP_ID)
        self.assertEqual(self.read_state()["volume_id"], VOLUME_ID)

    def test_one_remaining_resource_times_out_without_verified_success(self):
        for present_key in self.getters:
            with self.subTest(present_key=present_key):
                self.state["verified"] = False
                self.write_state(self.state)
                for key, getter in self.getters.items():
                    getter.reset_mock()
                    getter.side_effect = None if key == present_key else HTTPFailure(404)
                    getter.return_value = SimpleNamespace(id=self.state[key], port_id=None)

                with self.assertRaises(cleanup.CleanupError):
                    cleanup.verify(self.connection, self.state, self.state_path, timeout=20)

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
                self.fip_getter.assert_not_called()
                self.volume_getter.assert_not_called()

    def test_verification_rejects_missing_or_invalid_recorded_ids(self):
        for key in self.getters:
            for value in (None, "", "not-a-uuid"):
                with self.subTest(key=key, value=value):
                    state = {**self.state, key: value}

                    with self.assertRaises(cleanup.CleanupError):
                        cleanup.verify(self.connection, state, self.state_path, timeout=30)

                    self.lb_getter.assert_not_called()
                    self.fip_getter.assert_not_called()
                    self.volume_getter.assert_not_called()

    def test_verification_does_not_accept_cloud_errors_as_cleanup(self):
        for failing_key in self.getters:
            with self.subTest(failing_key=failing_key):
                for key, getter in self.getters.items():
                    getter.side_effect = HTTPFailure(403 if key == failing_key else 404)

                with self.assertRaises(cleanup.CleanupError) as raised:
                    cleanup.verify(self.connection, self.state, self.state_path, timeout=30)

                self.assertNotIn(RAW_BODY, str(raised.exception))
                self.assertIsNot(self.state.get("verified"), True)
                self.assertIsNot(self.read_state().get("verified"), True)


if __name__ == "__main__":
    unittest.main()
