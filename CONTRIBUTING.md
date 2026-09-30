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

### CAPI/CAPO API migration checks

Changes to CAPI/CAPO templates must also pass the [v1beta2 migration tests](docs/v1beta2-migration.md).
CI compares old and new chart output to check values compatibility and template names.
It also checks that configuration changes still update the affected templates.
Run the tests with Helm and Python with PyYAML.
Separate CI steps validate schemas with kubeconform.
