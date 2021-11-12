{{/*
Expand the name of the chart.
*/}}
{{- define "cluster-addons.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "cluster-addons.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create a fully qualified component name.
*/}}
{{- define "cluster-addons.componentName" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- if contains $ctx.Chart.Name $ctx.Release.Name }}
{{- printf "%s-%s" $ctx.Release.Name $componentName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s-%s" $ctx.Release.Name $ctx.Chart.Name $componentName | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cluster-addons.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels for a chart-level resource.
*/}}
{{- define "cluster-addons.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cluster-addons.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for a component-level resource.
*/}}
{{- define "cluster-addons.componentSelectorLabels" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- include "cluster-addons.selectorLabels" $ctx }}
app.kubernetes.io/component: {{ $componentName }}
{{- end }}

{{/*
Common labels for all resources.
*/}}
{{- define "cluster-addons.commonLabels" -}}
helm.sh/chart: {{ include "cluster-addons.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Labels for a chart-level resource.
*/}}
{{- define "cluster-addons.labels" -}}
{{ include "cluster-addons.commonLabels" . }}
{{ include "cluster-addons.selectorLabels" . }}
{{- end }}

{{/*
Component labels
*/}}
{{- define "cluster-addons.componentLabels" -}}
{{ include "cluster-addons.commonLabels" (index . 0) }}
{{ include "cluster-addons.componentSelectorLabels" . }}
{{- end }}

{{/*
Template for a config secret for use by a job that deploys an addon.
*/}}
{{- define "cluster-addons.job.config" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- $options := slice (append . dict) 2 | first }}
{{- $configSecretName := printf "%s-config" $componentName }}
{{- $configDataTemplate := printf "cluster-addons.%s.config" $componentName }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "cluster-addons.componentName" (list $ctx $configSecretName) }}
  labels: {{ include "cluster-addons.componentLabels" (list $ctx $componentName) | nindent 4 }}
stringData:
{{- if hasKey $options "configData" }}
{{- nindent 2 $options.configData }}
{{- else }}
{{- include $configDataTemplate $ctx | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Base template for a job that deploys an addon.
*/}}
{{- define "cluster-addons.job.base" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- $options := slice (append . dict) 2 | first }}
{{- $configSecretName := printf "%s-config" $componentName }}
{{- $scriptTemplate := printf "cluster-addons.%s.script" $componentName }}
{{- $bootstrap := dig "bootstrap" false $options }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "cluster-addons.componentName" (list $ctx $componentName) }}-{{ $ctx.Release.Revision }}
  labels: {{ include "cluster-addons.componentLabels" (list $ctx $componentName) | nindent 4 }}
spec:
  # Keep trying for a decent amount of time before failing
  backoffLimit: 1000
  # Keep succeeded jobs for 5m after finishing
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels: {{ include "cluster-addons.componentSelectorLabels" (list $ctx $componentName) | nindent 8 }}
    spec:
      # Ensure that we run as a non-root user
      securityContext:
        runAsUser: 1001
      serviceAccountName: {{ include "cluster-addons.componentName" (list $ctx "deployer") }}
      restartPolicy: OnFailure
      containers:
        - name: {{ $componentName }}
          image: {{ printf "%s:%s" $ctx.Values.jobImage.repository (default $ctx.Chart.AppVersion $ctx.Values.jobImage.tag) }}
          imagePullPolicy: {{ $ctx.Values.jobImage.pullPolicy }}
          args:
            - /bin/sh
            - -c
            - |
                set -exo pipefail
                {{- if hasKey $options "script" }}
                {{- nindent 16 $options.script }}
                {{- else }}
                {{- include $scriptTemplate $ctx | nindent 16 }}
                {{- end }}
          volumeMounts:
            - name: config
              mountPath: /config
              readOnly: true
      volumes:
        - name: config
          secret:
            secretName: {{ include "cluster-addons.componentName" (list $ctx $configSecretName) }}
      {{- if $bootstrap }}
      hostNetwork: true
      tolerations: {{ toYaml $ctx.Values.bootstrapTolerations | nindent 8 }}
      {{- end }}
{{- end }}

{{/*
Template for a job that deploys an addon.
*/}}
{{- define "cluster-addons.job" -}}
{{- $ctx := index . 0 }}
{{- $options := slice (append . dict) 2 | first }}
{{- $bootstrap := dig "bootstrap" false $options }}
{{- if or $bootstrap (not $ctx.Values.bootstrapOnly) }}
{{- include "cluster-addons.job.config" . }}
---
{{- include "cluster-addons.job.base" . }}
{{- end }}
{{- end }}

{{/*
Template for producing the configuration required for a Helm release.
*/}}
{{- define "cluster-addons.job.helm.config" -}}
values.yaml: |
  {{- toYaml .values | nindent 2 }}
{{- end }}

{{/*
Template for a script that installs or upgrades a Helm release.
*/}}
{{- define "cluster-addons.job.helm.script" -}}
{{- if hasKey . "crdManifests" -}}
get_chart_version() {
  helm show chart --repo {{ .chart.repo }} --version {{ .chart.version }} {{ .chart.name }} | \
    grep -e "^$1" | \
    cut -d ":" -f 2 | \
    tr -d '[:space:]'
}
CHART_VERSION="$(get_chart_version "version")"
CHART_APPVERSION="$(get_chart_version "appVersion")"
{{- range $manifestName := .crdManifests }}
kubectl apply -f {{ $.crdManifestsBaseURL }}/{{ $manifestName }}
{{- end }}
{{- end }}
helm upgrade {{ .release.name }} {{ .chart.name }} \
  --atomic --install \
  --namespace {{ .release.namespace }} --create-namespace \
  --repo {{ .chart.repo }} \
  --version {{ .chart.version }} \
  {{- if hasKey . "crdManifests" -}}
  --skip-crds \
  {{- end }}
  --values /config/values.yaml \
  --wait --timeout {{ .release.timeout }} \
  $HELM_EXTRA_ARGS
{{- end }}

{{/*
Template for a job that deploys an addon using a Helm chart.
*/}}
{{- define "cluster-addons.job.helm" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- $helmSpec := index . 2 }}
{{- $options := slice (append . dict) 3 | first }}
{{-
  include
    "cluster-addons.job"
    (list
      $ctx
      $componentName
      (merge
        (dict
          "configData" (include "cluster-addons.job.helm.config" $helmSpec)
          "script"     (include "cluster-addons.job.helm.script" $helmSpec)
        )
        $options
      )
    )
}}
{{- end }}

{{/*
Template for producing the configuration for an addon that uses kustomize.
*/}}
{{- define "cluster-addons.job.kustomize.config" -}}
{{- $ctx := index . 0 }}
{{- $kustomize := index . 1 }}
kustomization.yaml: |
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
  {{- range $kustomize.manifests }}
  - {{ tpl . $ctx }}
  {{- end }}
  {{- with $kustomize.kustomization }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}

{{/*
Template for producing a script for an addon that uses kustomize.
*/}}
{{- define "cluster-addons.job.kustomize.script" -}}
kustomize build /config | kubectl apply -f -
{{- range . }}
kubectl -n {{ index . 0 }} rollout status {{ index . 1 }}
{{- end }}
{{- end }}

{{/*
Template for a job that deploys an addon using kustomize.
*/}}
{{- define "cluster-addons.job.kustomize" -}}
{{- $ctx := index . 0 }}
{{- $componentName := index . 1 }}
{{- $kustomize := index . 2 }}
{{- $resources := index . 3 }}
{{- $options := slice (append . dict) 4 | first }}
{{-
  include
    "cluster-addons.job"
    (list
      $ctx
      $componentName
      (merge
        (dict
          "configData" (include "cluster-addons.job.kustomize.config" (list $ctx $kustomize))
          "script"     (include "cluster-addons.job.kustomize.script" $resources)
        )
        $options
      )
    )
}}
{{- end }}

{{/*
Template that merges two variables with the latter taking precedence and outputs the result as YAML.
Lists are merged by concatenating them rather than overwriting.
*/}}
{{- define "cluster-addons.mergeConcat" -}}
{{- $left := index . 0 }}
{{- if kindIs (kindOf list) $left }}
{{- index . 1 | default list | concat $left | toYaml }}
{{- else if kindIs (kindOf dict) $left }}
{{- $right := index . 1 | default dict }}
{{- range $key := concat (keys $left) (keys $right) | uniq }}
{{ $key }}:
  {{- if and (hasKey $left $key) (hasKey $right $key) }}
  {{-
    include "cluster-addons.mergeConcat" (list (index $left $key) (index $right $key)) |
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
