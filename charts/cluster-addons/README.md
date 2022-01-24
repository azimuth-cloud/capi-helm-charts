# cluster-addons chart

This [Helm chart](https://helm.sh/) manages the deployment of addons for a
[Kubernetes](https://kubernetes.io) cluster. It is primarily intended to be used with
the cluster management charts from this repository, e.g.
[openstack-cluster](../openstack-cluster), but should work for any Kubernetes cluster.

The addons are deployed by launching
[Kubernetes jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/), each of
which is responsible for installing or updating a single addon. These jobs can
either install the addons into the local cluster using a service account or a remote cluster
using a `kubeconfig` file in a pre-existing secret. By default, the local cluster is the
target.

The jobs use the [utils image](../../utils) from this repository, which bundles some
useful tools like [jq](https://stedolan.github.io/jq/),
[kubectl](https://kubernetes.io/docs/reference/kubectl/overview/),
[kustomize](https://kustomize.io/) and [helm](https://helm.sh).

When targetting the local cluster, the service account used to run the jobs must have
enough permissions to create all the objects that the addon will create. In practice,
this means that the service account will usually require the `cluster-admin` cluster role
for two reasons:

  1. This chart provides a mechanism to specify custom addons, and there is no way to
     know in advance what resources those custom addons may need to manage.
  1. This may even include instances of a
     [CRD](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
     that is installed by another addon.
  1. Several addons need to create
     [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) resources,
     and Kubernetes requires that the account creating RBAC resources has at least the
     permissions that it is attempting to apply to another account.

There are two patterns used in this chart for managing addons:

  1. Manifests are pulled from a URL and run through `kustomize` before being applied
     using `kubectl`. The manifests are **not** present in this repository. In this case,
     the URL and kustomize configuration can be changed using the Helm values if required,
     e.g. to change images from Docker Hub to another repository or to point to an
     internal source if an air-gapped installation is required.
  1. Using a Helm chart. The chart to use is configured using Helm values rather
     than Helm dependencies, which allows full control via configuration over which
     repository is used (e.g. a mirror for an air-gapped installation) and which version
     is installed. The Helm values for the addon are also exposed, and can be customised,
     via the values for this chart. This chart sets sensible defaults.

This chart also allows custom addons to be managed using the Helm values, either by
specifying manifest content inline, or by specifying a Helm chart to install with the
corresponding values.

## Targetting a remote cluster

By default, the jobs that install the addons target the local cluster using a service account.

It is also possible to target a remote cluster, using a `kubeconfig` file. This must first
be uploaded to the cluster as a secret:

```sh
kubectl create secret generic target-kubeconfig --from-file=kubeconfig=$PWD/kubeconfig
```

Then you can tell the addons to use that `kubeconfig` file using the Helm values:

```yaml
kubeconfigSecret:
  name: target-kubeconfig
  key: kubeconfig
```

## Container Network Interface (CNI) plugins

This chart can install either [Calico](https://docs.projectcalico.org/about/about-calico) or
[Cilium](https://cilium.io/) as a
[CNI plugin](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
to provide the pod networking in a Kubernetes cluster. By default, the Cilium CNI will be
installed.

To switch the CNI to Calico, use the following in your Helm values:

```yaml
cni:
  type: calico
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

This chart is able to deploy the CCM and the Cinder CSI plugin from the
[Kubernetes OpenStack cloud provider](https://github.com/kubernetes/cloud-provider-openstack),
which allows your Kubernetes cluster to integrate with the OpenStack cloud on which it is deployed.
This enables features like automatic labelling of nodes with OpenStack information (e.g. server ID
and flavor), automatic configuration of hostnames and IP addresses, managed load balancers for
services and dynamic provisioning of RWO volumes.

By default, the OpenStack integrations are not enabled. To enable OpenStack integrations on the
target cluster, use the following in your Helm values:

```yaml
openstack:
  enabled: true
```

To configure options for the `[Networking]`, `[LoadBalancer]`, `[BlockStorage]` and `[Metadata]`
sections of the cloud-config file, you can use Helm values, e.g.:

```yaml
openstack:
  cloudConfig: |
    [Networking]
    public-network-name=public-internet

    [LoadBalancer]
    lb-method=LEAST_CONNECTIONS
    create-monitor=true
    
    [BlockStorage]
    ignore-volume-az=true

    [Metadata]
    search-order=metadataService
```

The `[Globals]` section is populated using the given `clouds.yaml` (see "OpenStack credentials" below).

For the available options, consult the documentation for the
[CCM](https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/openstack-cloud-controller-manager/using-openstack-cloud-controller-manager.md#config-openstack-cloud-controller-manager)
and the
[Cinder CSI plugin](https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/cinder-csi-plugin/using-cinder-csi-plugin.md#block-storage).

Additional configuration options are available for the OpenStack integrations - see
[values.yaml](./values.yaml) for more details.

### OpenStack credentials

OpenStack credentials are required for the Kubernetes OpenStack integrations to query and
manage OpenStack resources on behalf of the cluster. The recommended way to do this is using an
[Application Credential](https://docs.openstack.org/keystone/latest/user/application_credentials.html)
to avoid your password being in stored on the cluster. Application credentials are project-scoped,
and ideally you should use a separate application credential for each cluster in a project.

When an application credential is created in Horizon, the corresponding `clouds.yaml` file can be
downloaded, and should look something like this:

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

The credentials are provided to this Helm chart by putting them into a secret:

```sh
kubectl create secret generic my-cloud-credential --from-file=clouds.yaml=$PWD/clouds.yaml
```

That secret can then be configured in the Helm values:

```yaml
openstack:
  cloudCredentialsSecretName: my-cloud-credential
```

The secret can also contain a certificate file that is used to validate the SSL certificate from
the target cloud:

```sh
kubectl create secret generic my-cloud-credential \
  --from-file=clouds.yaml=$PWD/clouds.yaml \
  --from-file=cacert=$PWD/ca.crt
```

Alternatively, certificate verification can be disabled in the `clouds.yaml`:

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
    verify: false
```

## cert-manager

This chart is able to install [cert-manager](https://cert-manager.io/) on the target cluster.
cert-manager provides custom resources for managing X509 certificates and certificate
issuers as native Kuberbetes resources, simplifying the issuance and renewal of X509
certificates (e.g. for TLS for web services). It is able to automatically negotiate
certificates from services such as [Let's Encrypt](https://letsencrypt.org/) by fulfilling
the required challenges, and can
[automatically issue certificates](https://cert-manager.io/docs/usage/ingress/) for
[Ingress resources](https://kubernetes.io/docs/concepts/services-networking/ingress/)
using annotations.

cert-manager is disabled by default. To enable it, use the following Helm values:

```yaml
certManager:
  enabled: true
```

By default, the installation includes a cluster issuer called `letsencrypt-http01` that
targets [Let's Encrypt](https://letsencrypt.org/) for certificate issuing.

Additional configuration options are available for cert-manager - see
[values.yaml](./values.yaml).

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

## Extra addons

This chart is able to manage the application of additional user-specified addons to the target
cluster. These can use Helm, Kustomize or a custom script to install and uninstall the addon,
and can even use a custom image containing specialist tools if required.

Each addon should have the form (not all options are required at all times):

```yaml
# One of helm, kustomize or custom
installType: custom
# Options for a Helm addon
helm:
  # List of URLs of manifests containing CRDs
  # Helm's handling of CRDs is not great - this helps if CRDs require updates
  crdManifests: []
  # The information for the Helm chart
  chart:
    # The URL of the chart repository
    repo:
    # The name of the chart
    name:
    # The version of the chart to use
    version:
  # Information about the Helm release
  release:
    # The namespace for the release on the target cluster
    namespace:
    # The name of the release
    name:
    # The time to wait for the Helm release to install correctly
    timeout: 60m
    # The values for the release
    # These can come from a dict or a template
    # The template is rendered with the root context, then the result is merged into the dict
    # Values from the template take precedence over the dict
    values: {}
    valuesTemplate:
# Options for a kustomize addon
kustomize:
  # The kustomize configuration
  # This can come from a dict or a template
  # The template is rendered with the root context, then the result is merged into the dict
  # Values from the template take precedence over the dict
  kustomization: {}
  kustomizationTemplate:
  # A list of resources to watch to determine when the addon has installed
  # These should be resources that can be used with "kubectl rollout status"
  # E.g. "deployment/my-deployment" or "statefulset/my-statefulset"
  resources: []
  # The namespace on the target cluster to watch resources in
  resourceNamespace:
# Options for a custom addon
custom:
  # Script that installs the addon
  # It is treated as a template, and rendered with the root context
  install:
  # Script that deletes the addon
  # It is also treated as a template and rendered with the root context
  delete:
# A list of extra sources to be added to the projected volume used for configuration
# The secrets and configmaps must already exist in the namespace
# https://kubernetes.io/docs/concepts/storage/projected-volumes/
extraVolumes: []
# A map of filename -> content of additional files to include in the config directory
extraFiles: {}
# Hook scripts that execute at certain times in the addon's lifecycle
# Hook scripts are treated as templates during rendering, and are rendered with the root context
hooks:
  # Executed before the addon is installed or upgraded
  preInstall:
  # Executed after the addon is installed or upgraded
  postInstall:
  # Executed before the addon is deleted
  preDelete:
  # Executed after the addon is deleted
  postDelete:
# Details of a custom image to use, if required
image:
  # The repository of the image
  repository:
  # The tag to use from the repository
  tag:
```

For example, the following extra addon will install a couple of additional manifests
into the cluster using Kustomize:

```yaml
extraAddons:
  custom-manifests:
    installType: kustomize
    kustomize:
      kustomization:
        resources:
          - ./storageclass-standard.yaml
          - ./pod-reader.yaml
    extraFiles:
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

Or to deploy a custom Helm release as part of the addon installation:

```yaml
extraAddons:
  my-wordpress:
    installType: helm
    helm:
      chart:
        repo: https://charts.bitnami.com/bitnami
        name: wordpress
        version: 12.1.6
      release:
        namespace: wordpress
        name: my-wordpress
        values:
          wordpressUsername: jbloggs
          wordpressPassword: supersecretpassword
          wordpressBlogName: JBloggs Awesome Blog!
```
