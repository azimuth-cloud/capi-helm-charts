# openstack-cluster chart  <!-- omit in toc -->

This [Helm chart](https://helm.sh/) manages the lifecycle of a [Kubernetes](https://kubernetes.io)
cluster on an [OpenStack](https://www.openstack.org/) cloud using
[Cluster API](https://cluster-api.sigs.k8s.io/).

As well as managing the Cluster API resources for the cluster, this chart optionally
manages addons for the cluster using addon resources from the
[Cluster API Addon Provider](https://github.com/azimuth-cloud/cluster-api-addon-provider).
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

## Contents  <!-- omit in toc -->

- [Prerequisites](#prerequisites)
- [OpenStack images](#openstack-images)
- [OpenStack credentials](#openstack-credentials)
- [Managing a workload cluster](#managing-a-workload-cluster)
- [Multiple external networks](#multiple-external-networks)
- [Volume-backed instances](#volume-backed-instances)
- [Etcd configuration](#etcd-configuration)
- [Load-balancer provider](#load-balancer-provider)
- [Cluster addons](#cluster-addons)
- [Accessing a workload cluster](#accessing-a-workload-cluster)
- [OpenID Connect authentication](#openid-connect-authentication)
  - [Creating an OIDC client](#creating-an-oidc-client)
  - [Configuring the cluster](#configuring-the-cluster)
  - [Connecting to the cluster](#connecting-to-the-cluster)
  - [Granting roles to users and groups from OIDC](#granting-roles-to-users-and-groups-from-oidc)
- [Configuring admission controllers](#configuring-admission-controllers)
  - [Configuring pod security standards](#configuring-pod-security-standards)
- [Troubleshooting](#troubleshooting)
- [Advanced](#advanced)
  - [Flatcar support](#flatcar-support)
  - [Keystone Authentication Webhook](#keystone-authentication-webhook)

## Prerequisites

First, you must set up a
[Cluster API management cluster](https://cluster-api.sigs.k8s.io/user/concepts.html#management-cluster)
with the [OpenStack Infrastructure Provider](https://github.com/kubernetes-sigs/cluster-api-provider-openstack)
installed.

Addons are managed by the
[Cluster API Addon Provider](https://github.com/azimuth-cloud/cluster-api-addon-provider),
which must also be installed if you wish to use the addons functionality.

In addition, Helm must be installed and configured to access your management cluster,
and the chart repository containing this chart must be configured:

```sh
helm repo add capi https://azimuth-cloud.github.io/capi-helm-charts
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

By default, this chart uses the same credentials for both, ensuring that the credential used for
Cluster API operations is propagated to the workload cluster.

The recommended way to do this is using an
[Application Credential](https://docs.openstack.org/keystone/latest/user/application_credentials.html)
to avoid your password being in stored on both the management and workload clusters.
Application credentials are project-scoped, and ideally you should use a separate
application credential for each cluster in a project.

For ease of use, this chart is written so that a `clouds.yaml` file can be given directly
to the chart as a configuration file. When an application credential is created in Horizon,
the corresponding `clouds.yaml` file can be downloaded, and should look something like this:

> [!WARNING]
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
kubernetesVersion: 1.29.2

# An image with the required software installed at the target version
machineImage: ubuntu-jammy-kube-v{{ .Values.kubernetesVersion }}

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
helm upgrade my-cluster capi/openstack-cluster --install -f ./clouds.yaml -f ./cluster-configuration.yaml
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

## Multiple external networks

When there is only one external network available to a project, Cluster API will attach
its router to that network and use it to allocate any floating IPs.

If the project you are using has multiple external networks available, you will need to
explicitly tell Cluster API which one to use:

```yaml
clusterNetworking:
  externalNetworkId: "<UUID of network>"
```

## Volume-backed instances

Flavors with significant root disks (> 40GB, ideally 100GB) are recommended for Kubernetes
nodes, as this is where downloaded images are stored which can be substantial in size.

If flavors with large root disks are not available, it is possible to use volume backed instances
instead.

> **WARNING**
>
> [etcd requires fast disks](https://etcd.io/docs/v3.5/op-guide/hardware/#disks) in order to
> operate reliably, so volume-backed instances are only appropriate if the storage system uses
> SSDs - **network-attached spinning disk will not be fast enough**.
>
> The recommended OpenStack configuration is to use local disk on the hypervisor for ephemeral
> root disks if possible.

To configure Kubernetes nodes to use volume-backed instances, use the following options:

```yaml
controlPlane:
  machineRootVolume:
    diskSize: 100
    volumeType: fast-ssd
    availabilityZone: nova

nodeGroupDefaults:
  machineRootVolume:
    diskSize: 100
    volumeType: fast-ssd
    availabilityZone: nova
```

## Etcd configuration

If you do not have much SSD capacity, it is possible to configure Kubernetes nodes so that
etcd is on a separate block device, using a different volume type. This allows the block
device that requires SSD to be much smaller.

To do this, use the following options:

```yaml
etcd:
  blockDevice:
    size: 10
    volumeType: fast-ssd
    availabilityZone: nova
```

This can be used in combination with volume-backed instances to get nodes that have a root
volume backed by spinning disk but with etcd on a volume backed by SSDs:

```yaml
etcd:
  blockDevice:
    size: 10
    volumeType: fast-ssd
    availabilityZone: nova

controlPlane:
  machineRootVolume:
    diskSize: 100
    volumeType: slow-platters
    availabilityZone: nova

nodeGroupDefaults:
  machineRootVolume:
    diskSize: 100
    volumeType: slow-platters
    availabilityZone: nova
```

## Load-balancer provider

If the target cloud uses the
[OVN Octavia driver](https://docs.openstack.org/ovn-octavia-provider/latest/admin/driver.html),
Kubernetes clusters should be configured to use OVN for any load-balancers that are created,
either by Cluster API or by the OpenStack Cloud Controller Manager for `LoadBalancer` services.
In addition, lb-method must be set to `SOURCE_IP_PORT`, as the OVN provder does not support the
default `ROUND_ROBIN`:

```yaml
apiServer:
  loadBalancerProvider: ovn

addons:
  openstack:
    cloudConfig:
      LoadBalancer:
        lb-provider: ovn
        lb-method: SOURCE_IP_PORT
```

## Cluster addons

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

To access the cluster, use `clusterctl` to fetch the kubeconfig file for the cluster:

```sh
# Generate a kubeconfig and write it to a file
clusterctl get kubeconfig my-cluster > kubeconfig.my-cluster
# Use that kubeconfig to list pods on the workload cluster
kubectl --kubeconfig=./kubeconfig.my-cluster get po -A
```

Note that this kubeconfig has full `cluster-admin` privileges, which are required by
Cluster API to do its work. If you want to grant more granular access to the cluster,
consider using OpenID Connect authentication.

## OpenID Connect authentication

Kubernetes is
[able to use](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens)
[OpenID Connect](https://openid.net/developers/how-connect-works/) tokens for authentication.

Using this mechanism, you can grant access to your Kubernetes cluster using any OIDC provider,
meaning that users can use their existing accounts to authenticate with the cluster. You can
then define Kubernetes [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
rules to grant access to users and groups from the OIDC provider in the same way that you would
for a service account for an application.

> **NOTE**
>
> A full introduction to OpenID Connect is beyond the scope of this document, and as such
> we assume some familiarity with the protocol. In particular, the reader should be familiar
> with the concepts of an OIDC client and the different
> [grant types](https://oauth.net/2/grant-types/) that are available.

### Creating an OIDC client

In order to configure your cluster to respect OIDC tokens, you must first create an OIDC client
with your authentication provider. The best practice is to use a client per cluster. This process
differs between authentication providers and is beyond the scope of this documentation. After
creating a client you will be given a client ID which we will use later.

When creating the client, you should [designate the client as public](https://oauth.net/2/client-types/),
indicating that the application that is using the client is not able to keep a client secret safe.
In our case, the application is `kubectl` on each individual user's machine, so this is clearly
the case.

If it is supported by your authentication provider, the
[Device Code](https://oauth.net/2/grant-types/device-code/) grant type is the best choice for
use from a terminal as it does not require a redirect URL, a local server, or a browser on
the machine running the command. The user must have access to a device with a browser in
order to authenticate with the authentication provider, but it does not have to be the same
machine that is running `kubectl`.

If the Device Code grant type is not available then the
[Authorization Code + PKCE](https://oauth.net/2/pkce/) flow can be used instead. This flow
requires the application to provide a callback URL that can receive the token - in a command-line
application like `kubectl`, this is achieved by launching a local HTTP server for the duration
of the authentication. You will need to supply `http://localhost:8000` as the redirect URL when
creating the client. The machine running `kubectl` must have a browser available in order to
open `http://localhost:8000` and follow the redirect chain for authentication.

### Configuring the cluster

Once you have created the OIDC client, you can configure the cluster to respect tokens issued for
the client by the authentication provider. To do this, you need the client ID and the
[discovery URL](https://swagger.io/docs/specification/authentication/openid-connect-discovery/)
for the authentication provider.

Setting the following values tells the Kubernetes API server to respect OIDC tokens for
authentication:

```yaml
oidc:
  # The discovery URL is https://auth.example.com/.well-known/openid-configuration
  issuerUrl: https://auth.example.com
  clientId: k8s-my-cluster
```

By default, the username will be taken from the `sub` claim and the user's groups from the
`groups` claim. These can be changed using the following values:

```yaml
oidc:
  usernameClaim: preferred_username
  groupsClaim: roles
```

### Connecting to the cluster

Once the cluster has been configured to respect OIDC tokens, it is then possible to create a
single kubeconfig file that can be distributed to users of the cluster and allows each of
those users to authenticate as themselves using the OIDC provider.

To do this, we use the
[exec support in kubeconfig](https://kubernetes.io/docs/reference/config-api/kubeconfig.v1/#ExecConfig)
to configure `kubectl` to fetch an OIDC token using the
[oidc-login](https://github.com/int128/kubelogin) plugin for `kubectl`. **Every user** of the
cluster must have this plugin installed in order to use the kubeconfig described below.

First, we must obtain the connection details for the Kubernetes API server. This can be done
by querying the Cluster API resources for the cluster:

```sh
CLUSTER=my-cluster
K8S_HOST="$(kubectl get cluster $CLUSTER -o go-template='{{.spec.controlPlaneEndpoint.host}}')"
K8S_PORT="$(kubectl get cluster $CLUSTER -o go-template='{{.spec.controlPlaneEndpoint.port}}')"
CADATA="$(kubectl get secret $CLUSTER-ca -o go-template='{{index .data "tls.crt"}}')"
```

Then we can create a kubeconfig file for connecting to the cluster using OIDC:

```yaml
apiVersion: v1
kind: Config
clusters:
  - cluster:
      certificate-authority-data: ${CADATA}
      server: https://${K8S_HOST}:${K8S_PORT}
    name: my-cluster
users:
  - name: oidc
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1beta1
        command: kubectl
        args:
          - oidc-login
          - get-token
          - --grant-type=device-code  # or authcode for Authorization Code + PKCE
          - --oidc-issuer-url=https://auth.example.com
          - --oidc-client-id=k8s-my-cluster
contexts:
- context:
    cluster: my-cluster
    user: oidc
  name: oidc@my-cluster
current-context: oidc@my-cluster
preferences: {}
```

This kubeconfig file can then be used to connect to the cluster. For example, you can see what
user Kubernetes thinks you have authenticated as:

```sh
$ kubectl auth whoami
ATTRIBUTE   VALUE
Username    oidc:jbloggs
Groups      [oidc:admins oidc:my-cluster-users system:authenticated]
```

When using the `device-code` grant type, a URL is generated for the user to visit to sign in to
the authentication provider and (if required) approve the application to use their data. If the
command is run on a machine with a browser this URL is opened automatically, otherwise the URL
is printed out and can be visited in the browser on another device.

When using the `authcode` grant type, the machine must have a browser available in order to
perform the authentication.

### Granting roles to users and groups from OIDC

By default, users from OIDC are not permitted to access any resources:

```sh
$ kubectl get po -A
Error from server (Forbidden): pods is forbidden: User "oidc:jbloggs" cannot list resource "pods" in API group "" at the cluster scope
```

Kubernetes [RBAC authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) can
be used to grant access to resources in Kubernetes for users and groups from OIDC. For example,
to grant all users with the `admins` group in their OIDC claims the `cluster-admin` role, the
following could be used:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    # Groups from OIDC have the prefix 'oidc:' in Kubernetes
    # This is to avoid collisions with other types of group
    # The same is true for users from OIDC
    name: oidc:admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
```

> A full discussion of Kubernetes RBAC authorization is beyond the scope of this document. Please
> consult the [official docs](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

If you want to manage a set of RBAC resources for OIDC users and groups as part of the cluster
deployment, this can be accomplished using a [custom addon](../cluster-addons/#custom-addons):

```yaml
addons:
  custom:
    oidc-rbac:
      kind: Manifests
      spec:
        namespace: oidc-system
        manifests:
          oidc-cluster-admin.yaml: |
            apiVersion: rbac.authorization.k8s.io/v1
            kind: ClusterRoleBinding
            metadata:
              name: oidc-cluster-admin
            subjects:
              - apiGroup: rbac.authorization.k8s.io
                kind: Group
                name: oidc:admins
            roleRef:
              apiGroup: rbac.authorization.k8s.io
              kind: ClusterRole
              name: cluster-admin
```

## Configuring admission controllers

An admission controller in Kubernetes has the ability to intercept API requests after
authentication and authorization but before the object is persisted, and is able to
modify and/or validate the object.

Kubernetes has a number of
[admission controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
that are used for things like
[enforcing quotas](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#resourcequota),
[setting the default storage class](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#resourcequota)
and
[enforcing pod security standards](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#podsecurity).

These charts allow the configuration of admiission controllers to be set when needed using
`apiServer.admissionConfiguration`. An example of using this to configure the default pod
security standard for the cluster is given below.

### Configuring pod security standards

The
[Pod Security admission controller](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
is responsible for checking pod definitions against the Kubernetes
[Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
before allowing them to enter the cluster.

By default, the `privileged` pod security standard applies, meaning that any pod is allowed to
be created in any namespace. The `baseline` and `restricted` standards have policies that pods
must meet to be permitted - see the Kubernetes documentation for the specific policies that apply
for each.

The standards can be applied in one of three modes:

  * `enforce` - policy violations cause the pod to be rejected
  * `audit` - policy violations are recorded in the audit log, if enabled
  * `warn` - policy violations trigger a user-facing warning

A different standard can be applied for each mode, e.g. enforce the `baseline` standard but
warn users when their workloads violate the `restricted` standard.

Pod security standards can be
[applied at the namespace level](https://kubernetes.io/docs/tutorials/security/ns-level-pss/)
using annotations on `Namespace` resources, but default standards can also be
[applied at the cluster level](https://kubernetes.io/docs/tutorials/security/cluster-level-pss/)
by passing configuration to the `PodSecurity` admission controller:

```yaml
apiServer:
  admissionConfiguration:
    PodSecurity:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      # The default standards for enforce, audit and warn
      defaults:
        enforce: baseline
        enforce-version: latest
        audit: baseline
        audit-version: latest
        warn: restricted
        warn-version: latest
      exemptions:
        # Any users who are exempt from the checks
        usernames: []
        # Any runtime classes that are exempt from the checks
        runtimeClasses: []
        # Any namespaces that are exempt from the checks
        namespaces:
          - kube-system
```

The configuration format is
[documented here](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/#configure-the-admission-controller).

## Troubleshooting

See [DEBUGGING.md](./DEBUGGING.md).

## Advanced

### Flatcar support

To deploy clusters which use Ignition such as Flatcar, you will need to override the following
setting in your local `values.yaml`:

```yaml
osDistro: flatcar
```

### Keystone Authentication Webhook

To deploy with the k8s-keystone-auth webhook enabled, set `authWebhook`
to "k8s-keystone-auth".

```
authWebhook: k8s-keystone-auth
```

See cluster-addons README for instructions on installing the `k8s-keystone-auth` subchart.
