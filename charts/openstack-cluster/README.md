# openstack-cluster chart

This [Helm chart](https://helm.sh/) manages the lifecycle of a [Kubernetes](https://kubernetes.io)
cluster on an [OpenStack](https://www.openstack.org/) cloud using
[Cluster API](https://cluster-api.sigs.k8s.io/).

As well as managing the Cluster API resources for the cluster, this chart optionally
manages addons for the cluster using addon resources from the
[Cluster API Addon Provider](https://github.com/stackhpc/cluster-api-addon-provider).
Some of these are required for a functional cluster, e.g. a
[Container Network Interface (CNI) plugin](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
and the
[OpenStack Cloud Controller Manager (CCM)](https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/openstack-cloud-controller-manager/using-openstack-cloud-controller-manager.md), and
others are optional.

> See the [cluster-addons chart](../cluster-addons) for more details about the addons
> that can be installed.

This README describes some of the basic options, however there are many other options
available. Check out the [values.yaml](./values.yaml) (commented) and the chart
templates for more details.

## Prerequisites

First, you must set up a
[Cluster API management cluster](https://cluster-api.sigs.k8s.io/user/concepts.html#management-cluster)
with the [OpenStack Infrastructure Provider](https://github.com/kubernetes-sigs/cluster-api-provider-openstack)
installed.

> **WARNING**
>
> This chart depends on features in
> [cluster-api-provider-openstack](https://github.com/kubernetes-sigs/cluster-api-provider-openstack)
> that are not yet in a release.
>
> StackHPC maintain custom builds of `cluster-api-provider-openstack` for use with this chart.
> You can find these in [the StackHPC fork](https://github.com/stackhpc/cluster-api-provider-openstack/releases)
> of `cluster-api-provider-openstack`.

Addons are managed by the
[Cluster API Addon Provider](https://github.com/stackhpc/cluster-api-addon-provider),
which must also be installed if you wish to use the addons functionality.

In addition, Helm must be installed and configured to access your management cluster,
and the chart repository containing this chart must be configured:

```sh
helm repo add capi https://stackhpc.github.io/capi-helm-charts
```

## OpenStack images

Cluster API uses an
[immutable infrastructure](https://www.hashicorp.com/resources/what-is-mutable-vs-immutable-infrastructure)
pattern where images are built with specific versions of the required
software installed (e.g.
[kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/),
[kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)).

Using this pattern, particularly with pre-built images, has some significant advantages, e.g.:

  * Creating, upgrading and (auto-)scaling of clusters is fast as the required software
    is already available in the image.
  * New images for operating system updates or new Kubernetes versions can be
    built and tested before being rolled out onto a production cluster with confidence
    that nothing has changed.
  * Images can be built and tested once and shared by multiple clusters.
  * Zero-downtime upgrades can be performed by replacing machines one at a time,
    with rollback if the upgrade fails.

Your cloud provider may use a centralised process to build, test and share suitable
images with all projects. If you need to build a suitable image, the
[Kubernetes Image Builder](https://image-builder.sigs.k8s.io/) project from the Cluster
Lifecycle SIG provides a tool for building images for use with Cluster API using
[QEMU](https://www.qemu.org/), [Packer](https://www.packer.io/) and [Ansible](https://www.ansible.com/).

## OpenStack credentials

OpenStack credentials are required for two purposes:

  1. For Cluster API to manage OpenStack resources for the workload cluster, e.g. networks, machines.
  2. For OpenStack integrations on the workload cluster, e.g. OpenStack CCM, Cinder CSI.

By default, this chart uses the same credentials for both.

The recommended way to do this is using an
[Application Credential](https://docs.openstack.org/keystone/latest/user/application_credentials.html)
to avoid your password being in stored on both the management and workload clusters.
Application credentials are project-scoped, and ideally you should use a separate
application credential for each cluster in a project.

For ease of use, this chart is written so that a `clouds.yaml` file can be given directly
to the chart as a configuration file. When an application credential is created in Horizon,
the corresponding `clouds.yaml` file can be downloaded, and should look something like this:

> WARNING
> 
> The Cluster API OpenStack provider currently requires that the `project_id` is present,
> which you will need to add manually.

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://my.cloud:5000
      project_id: "<project id>"
      application_credential_id: "<app cred id>"
      application_credential_secret: "<app cred secret>"
    region_name: "RegionOne"
    interface: "public"
    identity_api_version: 3
    auth_type: "v3applicationcredential"
```

This file can then be passed to the chart using the `-f|--values` option, e.g.:

```sh
helm install my-cluster capi/openstack-cluster --values ./clouds.yaml [...options]
```

## Managing a workload cluster

In addition to the `clouds.yaml`, the following is a minimal configuration to deploy a
working cluster:

```yaml
# The target Kubernetes version
kubernetesVersion: 1.22.1

# An image with the required software installed at the target version
machineImage: ubuntu-2004-kube-v{{ .Values.kubernetesVersion }}

# The name of the SSH keypair to inject into cluster machines
machineSSHKeyName: jbloggs-keypair

controlPlane:
  # The flavor to use for control plane machines
  # It is recommended to use a flavour with at least 2 CPU, 4GB RAM
  machineFlavor: vm.small

# A list of worker node groups for the cluster
nodeGroups:
  - # The name of the node group
    name: md-0
    # The flavor to use for the node group machines
    machineFlavor: vm.xlarge
    # The number of machines in the group
    machineCount: 3
```

To install or upgrade a cluster, use the following Helm command:

```sh
helm upgrade my-cluster capi/openstack-cluster --devel --install -f ./clouds.yaml -f ./cluster-configuration.yaml
```

This will create a cluster on its own network with a three node, highly-available (HA)
control plane, a load-balancer for the Kubernetes API with a floating IP attached
and a single worker group with three nodes.

To inspect the progress of the cluster deployment, you can use the
[clusterctl CLI](https://cluster-api.sigs.k8s.io/clusterctl/overview.html):

```sh
$ clusterctl describe cluster my-cluster
NAME                                                           READY  SEVERITY  REASON  SINCE  MESSAGE
/my-cluster                                                    True                     5d21h
├─ClusterInfrastructure - OpenStackCluster/my-cluster
├─ControlPlane - KubeadmControlPlane/my-cluster-control-plane  True                     5d21h
│ └─3 Machines...                                              True                     5d22h  See my-cluster-control-plane-77xg4, my-cluster-control-plane-stswh, ...
└─Workers
  └─MachineDeployment/my-cluster-md-0                          True                     5d22h
    └─3 Machines...                                            True                     5d22h  See my-cluster-md-0-8656cccd7b-4n2rq, my-cluster-md-0-8656cccd7b-dh7mc, ...
```

To update the cluster, just modify the configuration as required and run the above
command again. Some examples of updates that can be performed are:

  * Adding and removing node groups. A cluster can have several node groups, and
    each node group can have a different flavor and machine count.
  * Scaling the cluster. Change the machine count for the required node group(s)
    to add or remove machines.
  * Changing the image to update system packages or upgrade Kubernetes.
    Once a new image is available, change the machine image and Kubernetes version
    as required to trigger a rolling upgrade of the cluster nodes.

### Cluster addons

The cluster addons are enabled by default. You can configure which addons are deployed
and the configuration of those addons by specifying values for the addons Helm chart:

```yaml
addons:
  # Enable the Nginx ingress controller
  ingress:
    enabled: true
```

The available options under `addons` correspond to the chart values for the
[cluster-addons chart](../cluster-addons).

The cluster addons also can be disabled completely using the following configuration:

> **WARNING**
>
> If the cluster addons are disabled, you will need to manually install a CNI
> and the OpenStack Cloud Controller Manager before the cluster deployment will
> complete successfully.

```yaml
addons:
  enabled: false
```

## Accessing a workload cluster

To access the cluster, use `clusterctl` to generate a kubeconfig file:

```sh
# Generate a kubeconfig and write it to a file
clusterctl get kubeconfig my-cluster > kubeconfig.my-cluster
# Use that kubeconfig to list pods on the workload cluster
kubectl --kubeconfig=./kubeconfig.my-cluster get po -A
```

## Flatcar

To deploy clusters which use Ignition such as Flatcar, you will need to override the following setting in your local `values.yaml`:

```yaml
osDistro: flatcar 
```
