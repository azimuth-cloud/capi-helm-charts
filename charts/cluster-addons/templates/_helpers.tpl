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
Job specification for deploying an addon.
*/}}
{{- define "cluster-addons.job" -}}
{{- $ctx := index . 0 }}
{{- $jobName := index . 1 }}
{{- $jobOpts := index . 2 }}
{{- $jobType := default "script" $jobOpts.type }}
{{- $scriptTemplate := default (printf "cluster-addons.%s.script" $jobName) $jobOpts.scriptTemplate }}
{{- $helmOpts := default dict $jobOpts.helmOpts }}
{{- $helmValues := omit $helmOpts "chart" "release" }}
{{- $bootstrap := default false $jobOpts.bootstrap }}
{{- $cni := default false $jobOpts.cni }}
{{- if and (eq $jobType "helm") $helmValues }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "cluster-addons.componentName" (list $ctx $jobName) }}
  labels: {{ include "cluster-addons.componentLabels" (list $ctx $jobName) | nindent 4 }}
type: Opaque
stringData:
  values.yaml: |
    {{- toYaml $helmValues | nindent 4 }}
---
{{- end }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "cluster-addons.componentName" (list $ctx $jobName) }}-{{ $ctx.Release.Revision }}
  labels: {{ include "cluster-addons.componentLabels" (list $ctx $jobName) | nindent 4 }}
spec:
  # Keep trying for a decent amount of time before failing
  backoffLimit: 1000
  # Keep succeeded jobs for 5m after finishing
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels: {{ include "cluster-addons.componentSelectorLabels" (list $ctx $jobName) | nindent 8 }}
    spec:
      serviceAccountName: {{ include "cluster-addons.componentName" (list $ctx "deployer") }}
      restartPolicy: OnFailure
      containers:
        - name: {{ $jobName }}
          image: {{ printf "%s:%s" $ctx.Values.jobImage.repository (default $ctx.Chart.AppVersion $ctx.Values.jobImage.tag) }}
          imagePullPolicy: {{ $ctx.Values.jobImage.pullPolicy }}
          {{- if eq $jobType "helm" }}
          args:
            - helm
            - upgrade
            - {{ $helmOpts.release.name }}
            - {{ $helmOpts.chart.name }}
            - --install
            - --create-namespace
            - --namespace
            - {{ $helmOpts.release.namespace }}
            - --repo
            - {{ $helmOpts.chart.repo }}
            - --version
            - {{ $helmOpts.chart.version | quote }}
            - --wait
            - --timeout
            - {{ default "5m" $helmOpts.release.timeout | quote }}
          {{- if $helmValues }}
            - --values
            - /config/values.yaml
          volumeMounts:
            - name: helm-values
              mountPath: /config
              readOnly: true
          {{- end }}
          {{- else }}
          args:
            - /bin/sh
            - -c
            - |
                {{ include $scriptTemplate $ctx | indent 16 | trim }}
          {{- end }}
      {{- if and (eq $jobType "helm") $helmValues }}
      volumes:
        - name: helm-values
          secret:
            secretName: {{ include "cluster-addons.componentName" (list $ctx $jobName) }}
      {{- end }}
      {{- if or $bootstrap $cni }}
      tolerations: {{ $ctx.Values.bootstrapTolerations | toYaml | nindent 8 }}
      {{- end }}
      {{- if $cni }}
      hostNetwork: true
      {{- end }}
{{- end }}
