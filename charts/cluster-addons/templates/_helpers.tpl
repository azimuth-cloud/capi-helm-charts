{{/*
The name of the target cluster.
*/}}
{{- define "cluster-addons.clusterName" -}}
{{- .Values.clusterName | default .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create a name for a cluster component.
*/}}
{{- define "cluster-addons.componentName" -}}
{{- $ctx := index . 0 -}}
{{- $componentName := index . 1 -}}
{{- printf "%s-%s" $ctx.Release.Name $componentName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cluster-addons.chart" -}}
{{-
  printf "%s-%s" .Chart.Name .Chart.Version |
    replace "+" "_" |
    trunc 63 |
    trimSuffix "-" |
    trimSuffix "." |
    trimSuffix "_"
}}
{{- end }}

{{/*
Selector labels for component-level resources
*/}}
{{- define "cluster-addons.componentSelectorLabels" -}}
capi.stackhpc.com/cluster: {{ index . 0 | include "cluster-addons.clusterName" }}
capi.stackhpc.com/component: {{ index . 1 }}
{{- end -}}

{{/*
Labels for component-level resources
*/}}
{{- define "cluster-addons.componentLabels" -}}
helm.sh/chart: {{ index . 0 | include "cluster-addons.chart" }}
capi.stackhpc.com/managed-by: {{ (index . 0).Release.Service }}
{{ include "cluster-addons.componentSelectorLabels" . }}
{{- end -}}
