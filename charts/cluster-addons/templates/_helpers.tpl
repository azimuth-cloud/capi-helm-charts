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
