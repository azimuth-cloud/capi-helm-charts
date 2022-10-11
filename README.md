# capi-helm-charts

This repository contains [Helm charts](https://helm.sh/) for deploying [Kubernetes](https://kubernetes.io/)
clusters using [Cluster API](https://cluster-api.sigs.k8s.io/).

The charts are available from the `stackhpc.github.io/capi-helm-charts` repository:

```sh
helm repo add capi https://stackhpc.github.io/capi-helm-charts
helm install my-release capi/<chartname> [...options]
```

To list the available versions for the charts:

```sh
helm search repo capi --devel --versions
```

> **WARNING**
>
> The `openstack-cluster` chart depends on features in
> [cluster-api-provider-openstack](https://github.com/kubernetes-sigs/cluster-api-provider-openstack)
> that are merged but are not yet in a release.
>
> StackHPC maintain builds for cherry-picked versions of `cluster-api-provider-openstack` for use with
> these charts. You can find these in
> [the StackHPC fork](https://github.com/stackhpc/cluster-api-provider-openstack/releases).

Currently, the following charts are available:

| Chart | Description |
| --- | --- |
| [cluster-addons](./charts/cluster-addons) | Deploys addons into a Kubernetes cluster, e.g. CNI. |
| [openstack-cluster](./charts/openstack-cluster) | Deploys a Kubernetes cluster on an OpenStack cloud. |
