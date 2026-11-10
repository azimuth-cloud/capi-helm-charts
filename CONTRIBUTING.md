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
docker run -i --rm --user "$(id -u):$(id -g)" \
  -v "$PWD:/apps" --tmpfs /.cache \
  helmunittest/helm-unittest charts/cluster-addons charts/openstack-cluster -u
```

The `-u` option updates the existing snapshots.
The container runs as your user so it can create snapshot directories and update their files.

### Calico CRD tests

The lint workflow also runs installer and dependency tests without contacting a cluster.
Run them locally with Helm and Python:

```sh
python3 -m venv /tmp/capi-helm-tests
/tmp/capi-helm-tests/bin/pip install -r scripts/requirements-calico.txt
/tmp/capi-helm-tests/bin/python -m unittest discover -s scripts/tests -p 'test_calico_*.py' -v
```
