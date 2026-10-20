#!/bin/sh

helm repo add projectcalico https://docs.tigera.io/calico/charts
helm template calico-crds projectcalico/crd.projectcalico.org.v1 --version v3.33.0 | kubectl apply --server-side -f -

kubectl delete clusterrole/install-calico-crds
