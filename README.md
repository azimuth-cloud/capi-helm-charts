# capi-helm-charts
![Test](https://github.com/stackhpc/capi-helm-charts/actions/workflows/main.yaml/badge.svg?branch=main)
![Publish](https://github.com/stackhpc/capi-helm-charts/actions/workflows/publish-artifacts.yaml/badge.svg?branch=main)

This repository contains [Helm charts](https://helm.sh/) for deploying [Kubernetes](https://kubernetes.io/)
clusters using [Cluster API](https://cluster-api.sigs.k8s.io/).

The charts are available from the `stackhpc.github.io/capi-helm-charts` repository:

```sh
helm repo add capi https://stackhpc.github.io/capi-helm-charts
helm install my-release capi/<chartname> [...options]
```

To list the available versions for the charts:

```sh
helm search repo capi --versions
```

Currently, the following charts are available:

| Chart | Description |
| --- | --- |
| [cluster-addons](./charts/cluster-addons) | Deploys addons into a Kubernetes cluster, e.g. CNI. |
| [etcd-defrag](./charts/etcd-defrag/) | Installs a `CronJob` for running [etcd defragmentation](https://etcd.io/docs/v3.5/op-guide/maintenance/#defragmentation). |
| [openstack-cluster](./charts/openstack-cluster) | Deploys a Kubernetes cluster on an OpenStack cloud. |
