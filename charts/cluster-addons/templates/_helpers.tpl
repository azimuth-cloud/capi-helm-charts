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
Labels for a chart-level resource.
*/}}
{{- define "cluster-addons.labels" -}}
helm.sh/chart: {{ include "cluster-addons.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{ include "cluster-addons.selectorLabels" . }}
{{- end }}

{{/*
Renders the default job configuration.
*/}}
{{- define "cluster-addons.job.defaults" -}}
{{- with .Values.jobDefaults }}
{{- toYaml . }}
{{- end }}
{{- if .Values.kubeconfigSecret.name }}
kubeconfigSecret:
  name: {{ tpl .Values.kubeconfigSecret.name . }}
  {{- with .Values.kubeconfigSecret.key }}
  key: {{ . }}
  {{- end }}
{{- end }}
serviceAccountName: {{ tpl .Values.serviceAccount.name . }}
{{- end }}
