# cluster-addons chart

This [Helm chart](https://helm.sh/) manages the deployment of addons for a
[Kubernetes](https://kubernetes.io) cluster. It is primarily intended to be used with
the cluster management charts from this repository, e.g.
[openstack-cluster](../openstack-cluster), but should work for any Kubernetes cluster.

The addons are deployed by launching
[Kubernetes jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/) on the
target cluster, each of which is responsible for installing or updating a single addon.
The jobs use the [utils image](../../utils) from this repository, which bundles some
useful tools like [jq](https://stedolan.github.io/jq/),
[kubectl](https://kubernetes.io/docs/reference/kubectl/overview/),
[kustomize](https://kustomize.io/) and [helm](https://helm.sh), and the jobs execute
with full permissions on the cluster using the `cluster-admin` cluster role. This is
used rather than a more restrictive role for a few reasons:

  1. This chart provides a mechanism to apply custom addons, and there is no way to
     know in advance what resources those custom addons may need to manage.
  1. Addons may need to manage
     [CRD](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
     instances that are not covered by a more restrictive role.
  1. Several addons need to create
     [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) resources,
     and so could elevate their permissions anyway by creating new roles.

There are two patterns used in this chart for managing addons:

  1. Manifests are pulled from a URL and run through `kustomize` before being applied
     using `kubectl apply`. The manifests are **not** present in this repository. In
     this case, the URL and kustomize configuration can be changed using the Helm values
     if required, e.g. to change images from Docker Hub to another repository or to
     point to an internal source if an air-gapped installation is required.
  1. Using a Helm chart. The chart to use is configured using Helm values rather
     than Helm dependencies, which allows full control via configuration over which
     repository is used (e.g. a mirror for an air-gapped installation) and which version
     is installed. The Helm values for the addon are also exposed, and can be customised,
     via the values for this chart. This chart sets sensible defaults.

This chart also allows custom addons to be managed using the Helm values, either by
specifying manifest content inline, or by specifying a Helm chart to install with the
corresponding values.

## Container Network Interface (CNI) plugins

This chart can install either
[Calico](https://docs.projectcalico.org/about/about-calico) or
[Weave](https://www.weave.works/docs/net/latest/kubernetes/kube-addon/) as a
[CNI plugin](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
to provide the pod networking in a Kubernetes cluster. By default, the Calico CNI will be
installed.

To switch the CNI to Weave, use the following in your Helm values:

```yaml
cni:
  type: weave
```

And to disable the installation of a CNI completely:

```yaml
cni:
  enabled: false
```

Additional configuration options are available for each - see [values.yaml](./values.yaml).

## OpenStack integrations

Kubernetes allows cloud providers to provide various plugins to integrate with the
underlying infrastructure, for example
[Cloud Controller Managers (CCMs)](https://kubernetes.io/docs/concepts/architecture/cloud-controller/),
[Container Storage Interface (CSI) implementations](https://kubernetes-csi.github.io/docs/)
and [authenticating webhooks](https://kubernetes.io/docs/reference/access-authn-authz/webhook/).    

This chart is able to deploy the CCM from the
[Kubernetes OpenStack cloud provider](https://github.com/kubernetes/cloud-provider-openstack)
to integrate with the OpenStack cloud on which a Kubernetes cluster is deployed, allowing
features like automatic labelling of nodes with OpenStack information (e.g. server ID and flavor),
automatic configuration of hostnames and IP addresses and managed load balancers for services.

By default, the OpenStack integrations are not enabled. To enable OpenStack integrations the target
cluster, use the following in your Helm values:

```yaml
openstack:
  enabled: true
```

To configure options for `[Networking]`, `[LoadBalancer]` and `[Metadata]` sections of the
[cloud-config](https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/openstack-cloud-controller-manager/using-openstack-cloud-controller-manager.md#config-openstack-cloud-controller-manager)
file you can use the Helm values, e.g.:

```yaml
openstack:
  ccm:
    cloudConfig:
      networking:
        public-network-name: public-internet
      loadBalancer:
        lb-method: LEAST_CONNECTIONS
        create-monitor: "true"
      metadata:
        search-order: metadataService
```

The `[Globals]` section is populated using the given `clouds.yaml` (see "OpenStack credentials" below).

Additional configuration options are available for CCMs - see [values.yaml](./values.yaml).

### OpenStack credentials

OpenStack credentials are required for the Kubernetes OpenStack integrations to query and
manage OpenStack resources on behalf of the cluster. The recommended way to do this is using an
[Application Credential](https://docs.openstack.org/keystone/latest/user/application_credentials.html)
to avoid your password being in stored on the cluster. Application credentials are project-scoped,
and ideally you should use a separate application credential for each cluster in a project.

For ease of use, this chart is written so that a `clouds.yaml` file can be given directly
to the chart as a configuration file. When an application credential is created in Horizon,
the corresponding `clouds.yaml` file can be downloaded, and should look something like this:

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://my.cloud:5000
      application_credential_id: "<app cred id>"
      application_credential_secret: "<app cred secret>"
    region_name: "RegionOne"
    interface: "public"
    identity_api_version: 3
    auth_type: "v3applicationcredential"
```

This file can then be passed to the chart using the `-f|--values` option, e.g.:

```sh
helm install cluster-addons capi/cluster-addons --values ./clouds.yaml [...options]
```

## NVIDIA GPU operator

This chart is able to install the
[NVIDIA GPU operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
to provide access to NVIDIA GPUs from Kubernetes pods using the
[device plugin framework](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/).

When deployed, the GPU operator will detect nodes with NVIDIA GPUs and automatically install the
NVIDIA software components required to make the GPUs available to Kubernetes. This does not
require any special modifications to the image used to deploy the nodes.

The GPU operator is not enabled by default. To enable it, use the following Helm values:

```yaml
nvidiaGPUOperator:
  enabled: true
```

Because of the automatic detection and labelling of nodes with GPUs, there is no need to
manually label nodes. In the case where some nodes have GPUs and some do not, the GPU
operator will do the right thing without the need for manual intervention.

Additional configuration options are available for the NVIDIA GPU operator - see
[values.yaml](./values.yaml).

## Custom manifests

This chart is able to manage the application of custom user-specified manifests to the
cluster using `kubectl apply`. This can be useful to install cluster-specific resources
such as additional
[storage classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
or [RBAC rules](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

To apply custom manifests to the cluster as part of the addon installation, use something
similar to the following in your Helm values:

```yaml
# This should be a mapping of filenames to manifest content
customManifests:
  storageclass-standard.yaml: |
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
    name: standard
    provisioner: my-storage-provisioner

  pod-reader.yaml: |
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: pod-reader
    rules:
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "watch", "list"]
```

## Custom Helm charts

In addition to simple custom manifests, this chart is also able to manage additional
cluster-specific Helm releases.

To deploy a custom Helm release as part of the addon installation, use something similar
to the following in your Helm values:

```yaml
customHelmReleases:
  # This is the name of the release
  my-wordpress:
    chart:
      # The repository that the chart is in
      repo: https://charts.bitnami.com/bitnami
      # The name of the chart
      name: wordpress
      # The version of the chart to use
      # NOTE: THIS IS REQUIRED
      version: 12.1.6
    # The namespace for the release
    # If not given, this defaults to the release name
    namespace: wordpress
    # The amount of time to wait for the chart to deploy before rolling back
    timeout: 5m
    # The values for the chart
    values:
      wordpressUsername: jbloggs
      wordpressPassword: supersecretpassword
      wordpressBlogName: JBloggs Awesome Blog!
```
