{{- define "addon.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "addon.fullname" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- if $ctx.Values.fullnameOverride }}
{{- printf "%s-%s" $ctx.Values.fullnameOverride $componentName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default $ctx.Chart.Name $ctx.Values.nameOverride }}
{{- if contains $name $ctx.Release.Name }}
{{- printf "%s-%s" $ctx.Release.Name $componentName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s-%s" $ctx.Release.Name $name $componentName | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "addon.job.name" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- $operation := index . 2 }}
{{- $fullname := include "addon.fullname" (list $ctx $componentName) }}
{{- printf "%s-%s" $fullname $operation | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "addon.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "addon.selectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $componentName := index . 1 -}}
app.kubernetes.io/name: {{ include "addon.name" $ctx }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
app.kubernetes.io/component: {{ $componentName }}
{{- end }}

{{- define "addon.job.selectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $componentName := index . 1 -}}
{{- $operation := index . 2 -}}
{{ include "addon.selectorLabels" (list $ctx $componentName) }}
capi.stackhpc.com/operation: {{ $operation }}
{{- end }}

{{- define "addon.commonLabels" -}}
helm.sh/chart: {{ include "addon.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{- define "addon.labels" -}}
{{- $ctx := index . 0 -}}
{{ include "addon.commonLabels" $ctx }}
{{ include "addon.selectorLabels" . }}
{{- end }}

{{- define "addon.job.labels" -}}
{{- $ctx := index . 0 -}}
{{ include "addon.commonLabels" $ctx }}
{{ include "addon.job.selectorLabels" . }}
capi.stackhpc.com/revision: {{ $ctx.Release.Revision | quote }}
{{- end }}

{{/*
Template that merges two variables with the latter taking precedence and outputs the result as YAML.
Lists are merged by concatenating them rather than overwriting.
*/}}
{{- define "addon.mergeConcat" -}}
{{- $left := index . 0 }}
{{- if kindIs (kindOf list) $left }}
{{- index . 1 | default list | concat $left | toYaml }}
{{- else if kindIs (kindOf dict) $left }}
{{- $right := index . 1 | default dict }}
{{- if or $left $right }}
{{- range $key := concat (keys $left) (keys $right) | uniq }}
{{ $key }}:
  {{- if and (hasKey $left $key) (hasKey $right $key) }}
  {{-
    include "addon.mergeConcat" (list (index $left $key) (index $right $key)) |
    nindent 2
  }}
  {{- else if hasKey $left $key }}
  {{- index $left $key | toYaml | nindent 2 }}
  {{- else }}
  {{- index $right $key | toYaml | nindent 2 }}
  {{- end }}
{{- end }}
{{- else }}
{}
{{- end }}
{{- else }}
{{- $right := index . 1 }}
{{- kindIs "invalid" $right | ternary $left $right | toYaml }}
{{- end }}
{{- end }}

{{/*
Template for a Helm values file that consists of the given values merged with the
values obtained from rendering the valuesTemplate.
*/}}
{{- define "addon.helm.values" }}
{{- $ctx := index . 0 }}
{{- $config := index . 2 }}
{{- if $config.release.valuesTemplate }}
{{- $templateValues := tpl $config.release.valuesTemplate $ctx | fromYaml }}
{{- include "addon.mergeConcat" (list $config.release.values $templateValues) }}
{{- else }}
{{- toYaml $config.release.values }}
{{- end }}
{{- end }}

{{/*
Template for a script that installs or upgrades a Helm release.

Because Helm has poor support for CRDs, there is an option to apply CRD manifest URLs before
installing or upgrading the release. CRDs are installed using "kubectl create/replace"
rather than "kubectl apply" because CRDs with comprehensive schemas can easily become too
large for the last-applied-configuration annotation.

There is also support for rolling back an interrupted install or upgrade before proceeding
by checking for the pending-[install,upgrade] status.
*/}}
{{- define "addon.helm.install" -}}
{{- $name := index . 0 }}
{{- $config := index . 1 }}
{{-
  $chartRepo := required
    "chart.repo is required for a Helm job"
    $config.chart.repo
}}
{{-
  $chartName := required
    "chart.name is required for a Helm job"
    $config.chart.name
}}
{{-
  $chartVersion := required
    "chart.version is required for a Helm job"
    $config.chart.version
}}
{{-
  $releaseNamespace := required
    "release.namespace is required for a Helm job"
    $config.release.namespace
}}
{{- range $config.crdManifests }}
kubectl create -f {{ . }} || \
  kubectl replace -f {{ . }}
{{- end }}
helm-upgrade {{ $name }} {{ $chartName }} \
  --atomic \
  --install \
  --namespace {{ $releaseNamespace }} \
  --create-namespace \
  --repo {{ $chartRepo }} \
  --version {{ $chartVersion }} \
  {{- if $config.crdManifests -}}
  --skip-crds \
  {{- end }}
  --values values.yaml \
  --wait \
  --wait-for-jobs \
  --timeout 24h \
  $HELM_EXTRA_ARGS
{{- end }}

{{/*
Template for a script that deletes a Helm release.
*/}}
{{- define "addon.helm.delete" -}}
{{- $name := index . 0 }}
{{- $config := index . 1 }}
{{-
  $releaseNamespace := required
    "release.namespace is required for a Helm job"
    $config.release.namespace
}}
helm-delete {{ $name }} \
  --namespace {{ $releaseNamespace }} \
  --wait \
  --timeout 24h
{{- range $config.crdManifests }}
kubectl delete -f {{ . }}
{{- end }}
{{- end }}

{{/*
Template for a kustomization file for use with Kustomize.
*/}}
{{- define "addon.kustomize.kustomization" }}
{{- $ctx := index . 0 }}
{{- $config := index . 2 }}
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
{{- if $config.kustomizationTemplate }}
{{- $templateValues := tpl $config.kustomizationTemplate $ctx | fromYaml }}
{{ include "addon.mergeConcat" (list $config.kustomization $templateValues) }}
{{- else if $config.kustomization }}
{{ toYaml $config.kustomization }}
{{- else }}
{{- fail "One of kustomization or kustomizationTemplate is required for a Kustomize job" }}
{{- end }}
{{- end }}

{{/*
Template for a script that installs or upgrades resources using Kustomize.

Because kustomize has no release semantics, which we want, what we actually do is
convert the output of kustomize into an ephemeral Helm chart which is then installed
with no values.
*/}}
{{- define "addon.kustomize.install" }}
{{- $name := index . 0 }}
{{- $config := index . 1 }}
CHART_DIR="$(mktemp -d)"
kustomize build . | make-chart {{ $name }} "$CHART_DIR"
# Install the CRDs separately as Helm doesn't install updates
for crdfile in $(find "$CHART_DIR/crds" -name '*.yaml'); do
    kubectl create -f "$crdfile" || kubectl replace -f "$crdfile"
done
helm-upgrade {{ $name }} "$CHART_DIR" \
  --atomic \
  --install \
  --namespace kustomize-releases \
  --create-namespace \
  --skip-crds \
  --wait \
  --wait-for-jobs \
  --timeout 24h \
  $HELM_EXTRA_ARGS
{{- end }}

{{/*
Template for a script that deletes resources using Kustomize.

Because we are using Helm releases to manage resources templated by kustomize,
this just means deleting the Helm release. However we still want to run customize
in order to generate the CRDs that need deleting.
*/}}
{{- define "addon.kustomize.delete" }}
{{- $name := index . 0 }}
{{- $config := index . 1 }}
CHART_DIR="$(mktemp -d)"
kustomize build . | make-chart {{ $name }} "$CHART_DIR"
helm-delete {{ $name }} \
  --namespace kustomize-releases \
  --wait \
  --timeout 24h
for crdfile in $(find "$CHART_DIR/crds" -name '*.yaml'); do
    kubectl delete -f "$crdfile"
done
{{- end }}

{{/*
Template that produces the default configuration.
*/}}
{{- define "addon.config.defaults" -}}
# Indicates whether the addon is enabled or not
enabled: true
# A list of other addons that this addon should wait for before installing
dependsOn: []
# The weight to use for the uninstall hook
# This can be used to influence the order in which addons are deleted
uninstallHookWeight: 0
image:
  repository: ghcr.io/stackhpc/k8s-utils
  tag:  # Defaults to chart appVersion if not given
  pullPolicy: IfNotPresent
imagePullSecrets:
kubeconfigSecret:
  name:
  key: value
serviceAccountName:
# One of helm, kustomize or custom
installType: custom
helm:
  crdManifests: []
  chart:
    repo:
    name:
    version:
  release:
    namespace:
    # The template is rendered with the root context, then the result is merged into the dict
    # Values from the template take precedence over the dict
    values: {}
    valuesTemplate:
kustomize:
  # The template is rendered with the root context, then the result is merged into the dict
  # Values from the template take precedence over the dict
  kustomization: {}
  kustomizationTemplate:
custom:
  # Scripts are treated as templates during rendering
  install:
  delete:
extraVolumes: []
extraFiles: {}
# The hook scripts are treated as templates during the rendering
hooks:
  preInstall:
  postInstall:
  preDelete:
  postDelete:
# Extra containers to run as init containers
# These should include environment variables, volume mounts etc. if they need
# to target a remote cluster using kubeconfigSecret
extraInitContainers: []
backoffLimit: 1000
activeDeadlineSeconds: 3600
podSecurityContext:
  runAsNonRoot: true
securityContext:
  allowPrivilegeEscalation: false
resources: {}
hostNetwork: false
tolerations: []
nodeSelector: {}
affinity: {}
{{- end }}

{{/*
Template that produces a config secret, an install job and a hooks for the specified addon.

If the addon is enabled, an install job is produced as part of the main release and a pre-delete
hook is also produced.

If the addon is disabled, then we check if the config secret exists for the addon. If it does, a
pre-upgrade hook is produced to uninstall the addon.
*/}}
{{- define "addon.job.fromConfig" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
{{- $overrides := index . 2 }}
{{- $defaults := include "addon.config.defaults" $ctx | fromYaml }}
{{- $config := include "addon.mergeConcat" (list $defaults $overrides) | fromYaml }}
{{- if $config.enabled }}
{{- include "addon.config.secret" (list $ctx $name $config) }}
---
{{- include "addon.job.install" (list $ctx $name $config) }}
---
{{- include "addon.job.uninstall" (list $ctx $name "pre-delete" $config) }}
{{- else if $ctx.Release.IsUpgrade }}
{{- $secretName := include "addon.fullname" (list $ctx $name) | printf "%s-config" }}
{{- if lookup "v1" "Secret" $ctx.Release.Namespace $secretName }}
{{- include "addon.job.uninstall" (list $ctx $name "pre-upgrade" $config) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Template that produces a config secret, an install job and a delete hook
for the configuration produced by the specified template.
*/}}
{{- define "addon.job" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
{{- $configTemplate := index . 2 }}
{{- $config := include $configTemplate $ctx | fromYaml }}
{{- include "addon.job.fromConfig" (list $ctx $name $config) }}
{{- end }}
