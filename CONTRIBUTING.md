# Contributing

## Making a contribution

We welcome contributions and suggestions for improvements to these Helm charts.
Please check for relevant issues and PRs before opening a new one of your own.

The remainder of this document describes some of the tooling that is used for testing
and validation in this repo. Prospective contributors should read the relevant sections
carefully in order to make the contribution process as easy and efficient as possible.

## Helm values schema

The charts in this repository use Helm's JSON schema validation functionality to improve user
experience and catch basic formatting errors in Helm values files. The JSON schema are
generated using the [helm-schema](https://github.com/dadav/helm-schema) plugin and each chart's
default values.yaml file is annotated with various `@schema` comment blocks where the schema
generator is unable to infer the an appropriate schema from the default values alone.

When making changes to a chart's values.yaml file, the schema plugin will need to be installed
locally by following the [installation instructions](https://github.com/dadav/helm-schema?tab=readme-ov-file#installation)
and the chart schema will need to be updated by running `helm schema` (or `helm-schema` /
`docker run ...` depending on the installation method chosen). If a chart's values file format
is updated without regenerating the schema, the CI linting and templating checks will fail.

### Schema strictness

The generated schema is not intended to be as strict as possible. Instead, it is intentionally
vague in certain places to avoid being overly restrictive on the set of allowed config values;
this is particularly important when the provided config values are passed along to an external
system. For example, the OpenStack cloud credentials field is annotated as a generic object
rather than attempting to specify the exact schema for an OpenStack clouds.yaml file, since
this could feasibly change in future OpenStack versions:

```yaml
# Content for the clouds.yaml file
# @schema
# type: [object,null]
# @schema
clouds:
```

Similarly, fields which default to an empty map are constrained based on the kinds of values
which a chart consumer may choose to provide. For example, the `machineMetadata`
field is only constrained to be a generic object, since the user may wish to provide arbitrary
Kubernetes metadata here:

```yaml
# Global metadata items to add to each machine
# @schema
# additionalProperties: true
# @schema
machineMetadata: {}
```

In contrast, the `clusterAnnotations` field is constrained to a list of key-value pairs where
both keys and values must be strings, since Kubernetes only allows string values for resource
annotations:

```yaml
# Any extra annotations to add to the cluster
# @schema
# type: object
# patternProperties:
#   ".*":
#     type: string
# @schema
clusterAnnotations: {}
```

A full list of the available schema annotations can be found on the Helm schema plugin's
[README](https://github.com/dadav/helm-schema?tab=readme-ov-file#annotations).

## Helm template snapshots

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
