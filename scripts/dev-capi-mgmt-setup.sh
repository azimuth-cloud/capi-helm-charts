#!/bin/bash
set -euxo pipefail

REQUIRED_TOOLS=(curl jq kubectl helm clusterctl)

for cmd in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is not installed or not in PATH." >&2
        exit 1
    fi
done

# Read dependencies.json
DEPENDENCIES_JSON=$(cat dependencies.json)

# Parse JSON into bash variables
ADDON_PROVIDER=$(echo $DEPENDENCIES_JSON | jq -r '.["addon-provider"]')
AZIMUTH_IMAGES_TAG=$(echo $DEPENDENCIES_JSON | jq -r '.["azimuth-images"]')
CLUSTER_API=$(echo $DEPENDENCIES_JSON | jq -r '.["cluster-api"]')
CLUSTER_API_JANITOR_OPENSTACK=$(echo $DEPENDENCIES_JSON | jq -r '.["cluster-api-janitor-openstack"]')
CLUSTER_API_PROVIDER_OPENSTACK=$(echo $DEPENDENCIES_JSON | jq -r '.["cluster-api-provider-openstack"]')
OPENSTACK_RESOURCE_CONTROLLER=$(echo $DEPENDENCIES_JSON | jq -r '.["openstack-resource-controller"]')
CERT_MANAGER=$(echo $DEPENDENCIES_JSON | jq -r '.["cert-manager"]')

# Install cert manager
{
    helm upgrade cert-manager cert-manager \
      --install \
      --namespace cert-manager \
      --create-namespace \
      --repo https://charts.jetstack.io \
      --version $CERT_MANAGER \
      --set installCRDs=true \
      --wait \
      --timeout 10m
} || {
    kubectl -n cert-manager get pods |  awk '$1 && $1!="NAME" { print $1 }' | xargs -n1 kubectl -n cert-manager logs
    exit
}

# Install OpenStack Resource Controller
ORC_URL=https://github.com/k-orc/openstack-resource-controller/releases/download/${OPENSTACK_RESOURCE_CONTROLLER}/install.yaml
kubectl apply --server-side --force-conflicts -f ${ORC_URL}

# Install Cluster API resources
# NOTE: replace `init` with `upgrade apply`
# if CAPI management components are already
# installed on the target cluster
clusterctl init \
    --core cluster-api:$CLUSTER_API \
    --bootstrap kubeadm:$CLUSTER_API \
    --control-plane kubeadm:$CLUSTER_API \
    --infrastructure openstack:$CLUSTER_API_PROVIDER_OPENSTACK

# Install addon manager
helm upgrade cluster-api-addon-provider cluster-api-addon-provider \
  --install \
  --repo https://azimuth-cloud.github.io/cluster-api-addon-provider \
  --version $ADDON_PROVIDER \
  --namespace capi-addon-system \
  --create-namespace \
  --wait \
  --timeout 10m

# Install janitor
helm upgrade cluster-api-janitor-openstack cluster-api-janitor-openstack \
  --install \
  --repo https://azimuth-cloud.github.io/cluster-api-janitor-openstack \
  --version $CLUSTER_API_JANITOR_OPENSTACK \
  --namespace capi-janitor-system \
  --create-namespace \
  --wait \
  --timeout 10m
