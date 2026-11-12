#!/bin/sh
set -eu

: "${CALICO_CRD_VERSION:?CALICO_CRD_VERSION must be set}"

# Keep the URL on a release tag, never an arbitrary branch or path.
case "$CALICO_CRD_VERSION" in
  *[!v0-9.]*) printf '%s\n' "CALICO_CRD_VERSION must be a single release tag" >&2; exit 1 ;;
esac
if ! printf '%s\n' "$CALICO_CRD_VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  printf '%s\n' "CALICO_CRD_VERSION must be a release version such as v3.33.0" >&2
  exit 1
fi

crds_file="$(mktemp "${TMPDIR:-/tmp}/calico-crds.XXXXXX")"
objects_file=""
object_file=""
ordered_file=""
cleanup() {
  installer_status=$?
  trap - 0
  rm -f "$crds_file" || :
  if [ -n "$objects_file" ]; then rm -f "$objects_file" || :; fi
  if [ -n "$object_file" ]; then rm -f "$object_file" || :; fi
  if [ -n "$ordered_file" ]; then rm -f "$ordered_file" || :; fi
  exit "$installer_status"
}
trap cleanup 0

# These are the same v1 CRDs as the upstream crd.projectcalico.org.v1 chart.
# Client dry-run downloads and parses the manifest; it does not validate existing CRs.
# Use separate commands so an earlier failure cannot be hidden by a pipeline.
kubectl create --dry-run=client --validate=false \
  -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_CRD_VERSION}/manifests/v1_crd_projectcalico_org.yaml" \
  -o yaml > "$crds_file"

if [ ! -s "$crds_file" ]; then
  printf '%s\n' "Calico CRD manifest is empty" >&2
  exit 1
fi

# Bootstrap must not race an existing operator by replacing its CRD schemas.
# Print one JSON object per line, then create only objects that are missing.
# Client dry-run flattens a List and invokes the printer for each object.
objects_file="$(mktemp "${TMPDIR:-/tmp}/calico-crds.XXXXXX")"
object_file="$(mktemp "${TMPDIR:-/tmp}/calico-crds.XXXXXX")"
ordered_file="$(mktemp "${TMPDIR:-/tmp}/calico-crds.XXXXXX")"
kubectl create --dry-run=client --validate=false -f "$crds_file" \
  -o 'jsonpath={.spec.group}{"\t"}{@}{"\n"}' > "$objects_file"
if [ ! -s "$objects_file" ]; then
  printf '%s\n' "Calico CRD object list is empty" >&2
  exit 1
fi
# Establish the v1 Calico API before any operator can start and select CRD mode.
# The remaining groups are operator.tigera.io and policy.networking.k8s.io.
LC_ALL=C sort "$objects_file" > "$ordered_file"
while IFS="$(printf '\t')" read -r group object; do
  case "$group" in
    crd.projectcalico.org|operator.tigera.io|policy.networking.k8s.io) ;;
    *) printf '%s\n' "Unexpected CRD group: $group" >&2; exit 1 ;;
  esac
  printf '%s\n' "$object" > "$object_file"
  resource="$(kubectl create --dry-run=client --validate=false -f "$object_file" -o name)"
  case "$resource" in
    customresourcedefinition.apiextensions.k8s.io/*) ;;
    *) printf '%s\n' "Expected a single CustomResourceDefinition, got: $resource" >&2; exit 1 ;;
  esac
  existing="$(kubectl get "$resource" --ignore-not-found -o name)"
  if [ -z "$existing" ]; then
    kubectl create --field-manager=calico-crds-bootstrap -f "$object_file"
  fi
  kubectl wait --for=condition=Established --timeout=120s -f "$object_file"
done < "$ordered_file"
kubectl wait --for=condition=Established --timeout=120s -f "$crds_file"
