{{/*
Create a cluster name. The name of the cluster is just the release name.
*/}}
{{- define "openstack-cluster.clusterName" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create a name for a cluster component.
*/}}
{{- define "openstack-cluster.componentName" -}}
{{- $ctx := index . 0 -}}
{{- $componentName := index . 1 -}}
{{- printf "%s-%s" $ctx.Release.Name $componentName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openstack-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openstack-cluster.commonLabels" -}}
helm.sh/chart: {{ include "openstack-cluster.chart" . }}
capi.stackhpc.com/managed-by: {{ .Release.Service }}
capi.stackhpc.com/infrastructure-provider: openstack
capi.stackhpc.com/cluster: {{ include "openstack-cluster.clusterName" . }}
{{- end -}}

{{/*
Component labels
*/}}
{{- define "openstack-cluster.componentLabels" -}}
{{- $ctx := index . 0 -}}
{{- $componentName := index . 1 -}}
{{- include "openstack-cluster.commonLabels" $ctx }}
capi.stackhpc.com/component: {{ $componentName }}
{{- end -}}

{{/*
Control plane selector labels
*/}}
{{- define "openstack-cluster.controlPlaneSelectorLabels" -}}
capi.stackhpc.com/cluster: {{ include "openstack-cluster.clusterName" . }}
capi.stackhpc.com/component: control-plane
{{- end -}}

{{/*
Node group labels
*/}}
{{- define "openstack-cluster.nodeGroupLabels" -}}
{{- $ctx := index . 0 -}}
{{- $nodeGroupName := index . 1 -}}
{{- include "openstack-cluster.commonLabels" $ctx }}
capi.stackhpc.com/component: worker
capi.stackhpc.com/node-group: {{ $nodeGroupName }}
{{- end -}}

{{/*
Node group selector labels
*/}}
{{- define "openstack-cluster.nodeGroupSelectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $nodeGroupName := index . 1 -}}
capi.stackhpc.com/cluster: {{ include "openstack-cluster.clusterName" $ctx }}
capi.stackhpc.com/component: worker
capi.stackhpc.com/node-group: {{ $nodeGroupName }}
{{- end -}}

{{/*
Name of the cloud-config secret.
*/}}
{{- define "openstack-cluster.cloudConfigSecretName" -}}
{{- if .Values.cloudConfigSecretName -}}
{{- .Values.cloudConfigSecretName -}}
{{- else -}}
{{ include "openstack-cluster.componentName" (list . "cloud-config") -}}
{{- end -}}
{{- end -}}
