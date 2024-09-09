# cluster-addons chart  <!-- omit in toc -->

This [Helm chart](https://helm.sh/) manages the deployment of addons for a
[Kubernetes](https://kubernetes.io) cluster deployed using
[Cluster API](https://cluster-api.sigs.k8s.io/). It is a dependency of the cluster management
charts from this repository, e.g. [openstack-cluster](../openstack-cluster).

Addons are managed using custom resources provided by the
[Cluster API Addon Provider](https://github.com/azimuth-cloud/cluster-api-addon-provider),
which must be installed. Please also read the documentation for the addon provider to
see how addons are defined.

## Contents  <!-- omit in toc -->

- [Container Network Interface (CNI) plugins](#container-network-interface-cni-plugins)
- [OpenStack integrations](#openstack-integrations)
  - [Cinder CSI and storage class](#cinder-csi-and-storage-class)
  - [Manila CSI and storage class](#manila-csi-and-storage-class)
  - [Keystone authenticating webhook](#keystone-authenticating-webhook)
- [Ingress controllers](#ingress-controllers)
- [Metrics server](#metrics-server)
- [Monitoring and logging](#monitoring-and-logging)
- [Custom addons](#custom-addons)

## Container Network Interface (CNI) plugins

This chart can install either [Calico](https://docs.projectcalico.org/about/about-calico) or
[Cilium](https://cilium.io/) as a
[CNI plugin](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
to provide the pod networking in a Kubernetes cluster. By default, the Calico CNI will be
installed.

To switch the CNI to Cilium, use the following in your Helm values:

```yaml
cni:
  type: cilium
```

> **NOTE**
> 
> When Cilium is used, the
> [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
> is configured by default with no further action required.

To disable the installation of a CNI completely, use:

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

This chart is able to deploy the CCM, the Cinder and Manila CSI plugins and the Keystone
authenticating webbook from the
[Kubernetes OpenStack cloud provider](https://github.com/kubernetes/cloud-provider-openstack),
which allows your Kubernetes cluster to integrate with the OpenStack cloud on which it is deployed.
This enables features like automatic labelling of nodes with OpenStack information (e.g. server ID
and flavor), automatic configuration of hostnames and IP addresses, managed load balancers for
services and dynamic provisioning of RWO and RWX volumes.

By default, the OpenStack integrations are not enabled. To enable OpenStack integrations on the
target cluster, use the following in your Helm values:

```yaml
openstack:
  enabled: true
```

> **TIP**
>
> When using the [openstack-cluster chart](../openstack-cluster/), the OpenStack integrations
> are enabled by default in the values for the chart.

To configure options for the `[Networking]`, `[LoadBalancer]`, `[BlockStorage]` and `[Metadata]`
sections of the cloud-config file, you can use Helm values, e.g.:

```yaml
openstack:
  cloudConfig:
    Networking:
      public-network-name: public-internet
    LoadBalancer:
      lb-method: LEAST_CONNECTIONS
      create-monitor: true
    BlockStorage:
      ignore-volume-az: true
    Metadata:
      search-order: metadataService
```

The `[Globals]` section is populated such that the credential used by the `OpenStackCluster`
object is also used by OpenStack integration on the cluster.

For the available options, consult the documentation for the
[CCM](https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/openstack-cloud-controller-manager/using-openstack-cloud-controller-manager.md#config-openstack-cloud-controller-manager)
and the
[Cinder CSI plugin](https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/cinder-csi-plugin/using-cinder-csi-plugin.md#block-storage).

Additional configuration options are available for the OpenStack integrations - see
[values.yaml](./values.yaml) for more details.

### Cinder CSI and storage class

The [Cinder service](https://docs.openstack.org/cinder/latest/) in an OpenStack cloud provides
[block volumes](https://en.wikipedia.org/wiki/Block-level_storage) for workloads. These volumes
can only be attached to a single pod at once, referred to as read-write-one (RWO).

Cinder is available on the vast majority of OpenStack clouds, and so the Cinder CSI is installed
by default whenever the OpenStack integrations are enabled. As part of this, a default
[storage class](https://kubernetes.io/docs/concepts/storage/storage-classes/) is installed that
allows Cinder volumes to be requested and attached to pods using
[persistent volume claims](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims).
This storage class uses the default Cinder volume type and the `nova` availability zone, and
is configured as the default storage class for the cluster.

To change the Cinder availability zone or volume type for the default storage class, use the
following values:

```yaml
openstack:
  csiCinder:
    defaultStorageClass:
      availabilityZone: az1
      volumeType: fast-ssd
```

### Manila CSI and storage class

In contrast to Cinder, the [Manila service](https://docs.openstack.org/manila/latest/) provides
shared filesystems for cloud workloads. These volumes can be attached to multiple pods
simultaneously, referred to as read-write-many (RWX).

Because Manila is often not deployed on OpenStack clouds, it is not enabled by default even when
the OpenStack integrations are enabled. To enable the Manila CSI, set the following variable:

```yaml
openstack:
  csiManila:
    enabled: true
```

Manila supports multiple backends, but currently only the [CephFS](https://docs.ceph.com/en/latest/cephfs/)
backend is supported in the CAPI Helm charts. To utilise the CephFS support in the Manila CSI,
the CephFS CSI plugin must also be enabled:

```yaml
csi:
  cephfs:
    enabled: true
```

By default, this will result in the Manila CSI creating volumes using the `cephfs` share type. If
you need to use a different share type, use the following:

```yaml
openstack:
  csiManila:
    defaultStorageClass:
      parameters:
        type: cephfs_type
```

Any of the storage class parameters
[specified in the Manila CSI docs](https://docs.ceph.com/en/latest/cephfs/) can be given under
`openstack.csiManila.defaultStorageClass.parameters`. For example, to use the `kernel` mounter
rather than the default `fuse` mounter, which can help performance, use the following:

```yaml
openstack:
  csiManila:
    defaultStorageClass:
      parameters:
        cephfs-mounter: kernel
```

### Keystone authenticating webhook

The  [k8s-keystone-auth](https://github.com/heytrav/helm-charts/tree/main/charts/k8s-keystone-auth) 
webhook can be installed by enabling the `k8sKeystoneAuth` subchart. Note that you will need to provide
the **auth url** and **project id** for the Openstack tenant where you are deploying your cluster.

```yaml
openstack:
  k8sKeystoneAuth:
    enabled: true
    values:
      openstackAuthUrl: $OS_AUTH_URL
      projectId: $OS_PROJECT_ID
```

## Ingress controllers

Running an
[Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
on your Kubernetes cluster enables the use of
[Ingress resource](https://kubernetes.io/docs/concepts/services-networking/ingress/)
to manage HTTP(S) traffic flowing in and out of the cluster. This allows your web applications
to take advantage of load-balancing, name-based virtual hosting, path-based routing and
TLS termination using the same declarative approach as other Kubernetes resources.
When combined with a cert-manager issuer (see above) this provides an almost frictionless way
to secure your web services.

It is possible to install multiple Ingress Controllers and select the preferred one for a
particular Ingress resource using
[Ingress Classes](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class).

This chart can install the [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
onto the target cluster.

The Nginx Ingress Controller is disabled by default. To enable it, use the following Helm values:

```yaml
ingress:
  enabled: true
```

## Metrics server

In order to use features like `kubectl top` to observe resource usage, and also to use
[Horizontal Pod Autoscalers](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/),
the [metrics server](https://github.com/kubernetes-sigs/metrics-server) must be installed.

This chart is able to install the metrics server, and it is enabled by default. To disable
it, use the following Helm values:

```yaml
metricsServer:
  enabled: false
```

## Monitoring and logging

This chart is able to deploy a monitoring and logging stack using
[Prometheus](https://prometheus.io/), [Grafana](https://grafana.com/) and
[Loki](https://github.com/grafana/loki).

The monitoring stack is installed using the
[kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack),
which makes sure many useful exporters are installed and dashboards available for them.
It also configures alerts for the cluster, *but does not configure any alert sinks by default*.

Loki is installed using the
[loki-stack](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack) chart,
that also installs and configures [promtail](https://grafana.com/docs/loki/latest/clients/promtail/)
to ship logs to Loki. A simple dashboard is installed into the Grafana provided by
`kube-prometheus-stack` to make the logs available for browsing.

The monitoring stack is not enabled by default. To enable it, use the following Helm values:

```yaml
monitoring:
  enabled: true
```

By default, Grafana is only available from within the cluster and must be accessed using
[port forwarding](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/):

```sh
kubectl -n monitoring-system port-forward svc/kube-prometheus-stack-grafana 3000:80
```

## Custom addons

This chart is able to manage the deployment of custom addons.

For example, to manage the deployment of a custom Helm chart:

```yaml
custom:
  # This is the name of the Helm release
  my-custom-helm-release:
    kind: HelmRelease
    spec:
      # The namespace for the release
      namespace: my-namespace
      # The chart to use
      chart:
        repo: https://my-project/charts
        name: my-chart
        version: 1.5.0
      # The values to use for the release
      values:
        name1: value1
        name2:
          complex:
            nested:
              - value
```

It is also possible to manage the deployment of arbitrary manifests to the cluster. The manifests
are managed by creating a Helm chart and release using them, and the Helm release manages the
lifecycle of the resulting resources. To specify custom manifests to install:

```yaml
custom:
  # The name of the Helm release that will contain the resources
  my-custom-manifests:
    kind: Manifests
    spec:
      # The namespace for the Helm release that will contain the resources
      # For namespace-scoped resources, this is the namespace that the resources will be created
      # in (unless overridden in the manifest itself)
      namespace: my-namespace
      manifests:
        secret.yaml: |-
          apiVersion: v1
          kind: Secret
          metadata:
            name: my-secret
          stringData:
            secret-file: "secret-data"
```
