# Contributing

We welcome contributions and suggestions for improvements to these Helm charts.
Please check for relevant issues and PRs before opening a new one of your own.

## Making a contribution

### Helm template snapshots

The CI in this repository uses the Helm [unittest](https://github.com/helm-unittest/helm-unittest)
plugin's snapshotting functionality to check PRs for changes to the templated manifests.
Therefore, if your PR makes changes to the manifest templates or values, you will need to update
the saved snapshots to allow your changes to pass the automated tests. The easiest way to do this
is to run the helm unittest command inside a docker container from the repo root.

```
helm dependency update charts/openstack-cluster
docker run -i --rm -v $(pwd):/apps helmunittest/helm-unittest charts/openstack-cluster -u
```

where the `-u` option is used to update the existing snapshots. If you receive
permissions errors when trying to update snapshots, ensure that you are using
the latest version of the `helmunittest/helm-unittest` image.

### Janitor in CI

The CI management cluster installs the [Go Janitor](https://github.com/azimuth-cloud/capi-janitor-openstack-go) from `oci://quay.io/azimuth/cluster-api-janitor-openstack-charts/cluster-api-janitor-openstack`.
Its chart version is pinned by `capi-janitor-openstack-go` in `dependencies.json`.
CI currently uses the `0.1.0-rc.1` chart.
Update this pin manually after a new chart has been published to Quay.
Chart versions omit the leading `v` used by Git tags.
The chart and its controller image must be publicly accessible to CI.

The separate dependency key keeps the Go version when upgrade tests merge dependencies from an older release.
The local `scripts/hacking-setup.sh` script continues to use the Python Janitor version in `cluster-api-janitor-openstack`.

The `scripts/janitor-cleanup.py` script is a CI regression test, separate from Helm installation and useful after the migration.
It uses Python and the OpenStack SDK, as `scripts/ensure-flatcar-sysext-images.py` already does, to distinguish missing resources from authentication and API errors.

The `latest` test job creates a LoadBalancer Service and a Pod with a Cinder PVC in the workload cluster.
It records their OpenStack IDs, enables volume deletion for that test cluster, and leaves the Service and PVC in place when deleting the cluster.
After deletion, the test waits for both IDs to return HTTP 404 from OpenStack.
The state file and controller logs are uploaded for diagnosis, including when the test fails.

This checks cleanup through OCCM, Cinder CSI and Go Janitor together.
Janitor's own integration suite separately checks resources without workload controllers managing them.
Run the cloud test only in the disposable CI cluster and allow quota for one additional load balancer and one 1 GiB volume.
If the test fails, use its recorded IDs to investigate and remove any remaining test resources.
The test does not delete cloud resources itself after checking them.

Run the offline checks without OpenStack or Kubernetes access:

```sh
python3 -m unittest discover -s scripts/tests -p 'test_janitor_cleanup.py' -v
```

These checks validate the test logic. A passing cloud CI run is still required before declaring the Go Janitor replacement tested.
