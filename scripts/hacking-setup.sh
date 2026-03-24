#!/usr/bin/env bash

DEPENDENCIES_PATH="$( dirname -- "$( readlink -f -- "$0"; )"; )/../dependencies.json"

echo "Retrieving dependencies from $DEPENDENCIES_PATH"

addon_provider="$(jq -r '.["addon-provider"]' "$DEPENDENCIES_PATH")"
cluster_api="$(jq -r '.["cluster-api"]' "$DEPENDENCIES_PATH")"
cluster_api_janitor_openstack="$(jq -r '.["cluster-api-janitor-openstack"]' "$DEPENDENCIES_PATH")"
cluster_api_provider_openstack="$(jq -r '.["cluster-api-provider-openstack"]' "$DEPENDENCIES_PATH")"
cert_manager="$(jq -r '.["cert-manager"]' "$DEPENDENCIES_PATH")"
helm="$(jq -r '.["helm"]' "$DEPENDENCIES_PATH")"
sonobuoy="$(jq -r '.["sonobuoy"]' "$DEPENDENCIES_PATH")"

helm upgrade cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --version ${cert_manager} \
  --namespace cert-manager \
  --create-namespace  \
  --install \
  --set installCRDs=true \
  --wait \
  --timeout 10m

curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/${cluster_api}/clusterctl-linux-amd64 -o clusterctl && chmod +x clusterctl
./clusterctl version

capi_function="init"
if kubectl get provider -n capi-system cluster-api; then
  capi_function="upgrade apply"
fi

./clusterctl ${capi_function} \
  --core cluster-api:${cluster_api} \
  --control-plane kubeadm:${cluster_api} \
  --bootstrap kubeadm:${cluster_api} \
  --infrastructure openstack:${cluster_api_provider_openstack} \
  --wait-providers

helm upgrade cluster-api-addon-provider cluster-api-addon-provider \
  --repo https://azimuth-cloud.github.io/cluster-api-addon-provider \
  --version ${addon_provider} \
  --namespace capi-addon-system \
  --create-namespace \
  --install \
  --wait \
  --timeout 10m

helm upgrade cluster-api-janitor-openstack cluster-api-janitor-openstack \
  --repo https://azimuth-cloud.github.io/cluster-api-janitor-openstack \
  --version ${cluster_api_janitor_openstack} \
  --namespace capi-janitor-system \
  --create-namespace \
  --install \
  --wait \
  --timeout 10m

