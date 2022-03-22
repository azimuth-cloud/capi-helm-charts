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
Name of the secret containing the cloud credentials.
*/}}
{{- define "openstack-cluster.cloudCredentialsSecretName" -}}
{{- if .Values.global.cloudCredentialsSecretName -}}
{{- .Values.global.cloudCredentialsSecretName -}}
{{- else -}}
{{ include "openstack-cluster.componentName" (list . "cloud-credentials") -}}
{{- end -}}
{{- end -}}

{{/*
Produces the spec for a KubeadmConfig object, with support for configuring registry
mirrors and additional packages.
*/}}
{{- define "openstack-cluster.kubeadmConfigSpec" -}}
{{- $ctx := index . 0 }}
{{- $registryMirrors := $ctx.Values.registryMirrors }}
{{- $additionalPackages := $ctx.Values.additionalPackages }}
{{- $kubeadmConfigSpec := omit (index . 1) "files" "preKubeadmCommands" }}
{{- $files := index . 1 | dig "files" list }}
{{- $preKubeadmCommands := index . 1 | dig "preKubeadmCommands" list }}

{{- with $kubeadmConfigSpec }}
{{- toYaml . }}
{{- end }}
files:
  - path: /etc/containerd/conf.d/.keepdir
    content: |
      # This file is created by the capi-helm-chart to
      # ensure that its parent directory exists. *.toml
      # files in this directory are included in containerd
      # config when /etc/containerd/config.toml is parsed.
    owner: root:root
    permissions: "0644"
{{- if $registryMirrors }}
  - path: /etc/containerd/conf.d/mirrors.toml
    content: |
      version = 2
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        {{- range $registry, $mirrors := $registryMirrors }}
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."{{ $registry }}"]
          endpoint = [{{ range $i, $mirror := $mirrors }}{{- if gt $i 0 }},{{ end }}"{{ . }}"{{- end }}]
        {{- end }}
    owner: root:root
    permissions: "0644"
{{- end }}
{{- if $files }}
  {{- range $files }}
  - {{ toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- if or $additionalPackages $preKubeadmCommands }}
preKubeadmCommands:
  {{- if $additionalPackages }}
  - apt update -y
  - apt install -y {{ join " " $additionalPackages }}
  {{- end }}
  {{- range $preKubeadmCommands }}
  - {{ . }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Produces the image for the cluster autoscaler.
*/}}
{{- define "openstack-cluster.autoscaler.image" -}}
{{- $tag := include "openstack-cluster.autoscaler.imageTag" . -}}
{{- printf "%s:%s" .Values.autoscaler.image.repository $tag -}}
{{- end }}

{{/*
Produces the image tag for the cluster autoscaler.

If an explicit tag is given that is used, otherwise a tag is derived from the
version of the target cluster.
*/}}
{{- define "openstack-cluster.autoscaler.imageTag" -}}
{{- if .Values.autoscaler.image.tag -}}
{{- .Values.autoscaler.image.tag -}}
{{- else -}}
{{- $kubeMinorVersion := .Values.global.kubernetesVersion | splitList "." | reverse | rest | reverse | join "." -}}
{{- $defaultTag := printf "v%s.0" $kubeMinorVersion -}}
{{- .Values.autoscaler.image.tags | dig $kubeMinorVersion $defaultTag -}}
{{- end -}}
{{- end }}
