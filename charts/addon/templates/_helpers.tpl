{{- define "addon.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "addon.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "addon.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "addon.selectorLabels" -}}
app.kubernetes.io/name: {{ include "addon.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "addon.jobSelectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $operation := index . 1 -}}
{{ include "addon.selectorLabels" $ctx }}
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
{{ include "addon.commonLabels" . }}
{{ include "addon.selectorLabels" . }}
{{- end }}

{{- define "addon.jobLabels" -}}
{{- $ctx := index . 0 -}}
{{ include "addon.commonLabels" $ctx }}
{{ include "addon.jobSelectorLabels" . }}
{{- end }}

{{/*
Template that prints the configured image.
*/}}
{{- define "addon.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
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
{{- default $left (index . 1) | toYaml }}
{{- end }}
{{- end }}

{{/*
Template for a Helm values file that consists of the given values merged with the
values obtained from rendering the valuesTemplate.
*/}}
{{- define "addon.helm.values" }}
{{- if .Values.helm.release.valuesTemplate }}
{{- $templateValues := tpl .Values.helm.release.valuesTemplate . | fromYaml }}
{{- include "addon.mergeConcat" (list .Values.helm.release.values $templateValues) }}
{{- else }}
{{- toYaml .Values.helm.release.values }}
{{- end }}
{{- end }}

{{/*
Template for a script that installs or upgrades a Helm release.

Because Helm has poor support for CRDs, there is an option to apply CRD manifest URLs before
installing or upgrading the release.

There is also support for rolling back an interrupted install or upgrade before proceeding
by checking for the pending-[install,upgrade] status.
*/}}
{{- define "addon.helm.install" -}}
{{-
  $chartRepo := required
    ".Values.helm.chart.repo is required for a Helm job"
    .Values.helm.chart.repo
}}
{{-
  $chartName := required
    ".Values.helm.chart.name is required for a Helm job"
    .Values.helm.chart.name
}}
{{-
  $chartVersion := required
    ".Values.helm.chart.version is required for a Helm job"
    .Values.helm.chart.version
}}
{{-
  $releaseNamespace := required
    ".Values.helm.release.namespace is required for a Helm job"
    .Values.helm.release.namespace
}}
{{-
  $releaseName := required
    ".Values.helm.release.name is required for a Helm job"
    .Values.helm.release.name
}}
{{- $releaseTimeout := .Values.helm.release.timeout -}}
{{- range .Values.helm.crdManifests }}
kubectl apply -f {{ . }}
{{- end }}
helm-upgrade {{ $releaseName }} {{ $chartName }} \
  --atomic \
  --install \
  --namespace {{ $releaseNamespace }} \
  --create-namespace \
  --repo {{ $chartRepo }} \
  --version {{ $chartVersion }} \
  {{- if .Values.helm.crdManifests -}}
  --skip-crds \
  {{- end }}
  --values values.yaml \
  --wait \
  --wait-for-jobs \
  --timeout {{ $releaseTimeout }} \
  $HELM_EXTRA_ARGS
{{- end }}

{{/*
Template for a script that deletes a Helm release.
*/}}
{{- define "addon.helm.delete" -}}
{{-
  $releaseNamespace := required
    ".Values.helm.release.namespace is required for a Helm job"
    .Values.helm.release.namespace
}}
{{-
  $releaseName := required
    ".Values.helm.release.name is required for a Helm job"
    .Values.helm.release.name
}}
{{- $releaseTimeout := .Values.helm.release.timeout -}}
helm-delete {{ $releaseName }} \
  --namespace {{ $releaseNamespace }} \
  --wait \
  --timeout {{ $releaseTimeout }}
{{- range .Values.helm.crdManifests }}
kubectl delete -f {{ . }}
{{- end }}
{{- end }}

{{/*
Template for a kustomization file for use with Kustomize.
*/}}
{{- define "addon.kustomize.kustomization" }}
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
{{- if .Values.kustomize.kustomizationTemplate }}
{{- $templateValues := tpl .Values.kustomize.kustomizationTemplate . | fromYaml }}
{{- include "addon.mergeConcat" (list .Values.kustomize.kustomization $templateValues) }}
{{- else if .Values.kustomize.kustomization }}
{{- toYaml .Values.kustomize.kustomization }}
{{- else }}
{{- fail "One of .Values.kustomize.kustomization or .Values.kustomize.kustomizationTemplate is required for a Kustomize job" }}
{{- end }}
{{- end }}

{{/*
Template for a script that installs or upgrades resources using Kustomize.
*/}}
{{- define "addon.kustomize.install" }}
kustomize build . | kubectl apply -f -
{{- if .Values.kustomize.resources }}
{{-
  $namespace := required
    ".Values.kustomize.resourceNamespace is required for a Kustomize job with resources"
    .Values.kustomize.resourceNamespace
}}
{{- range .Values.kustomize.resources }}
kubectl -n {{ $namespace }} rollout status {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Template for a script that deletes resources using Kustomize.
*/}}
{{- define "addon.kustomize.delete" }}
kustomize build . | kubectl delete -f -
{{- if .Values.kustomize.resources }}
{{-
  $namespace := required
    ".Values.kustomize.resourceNamespace is required for a Kustomize job with resources"
    .Values.kustomize.resourceNamespace
}}
{{- range .Values.kustomize.resources }}
kubectl -n {{ $namespace }} wait --for=delete {{ . }}
{{- end }}
{{- end }}
{{- end }}
