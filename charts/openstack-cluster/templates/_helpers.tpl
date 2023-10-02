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
{{ .Values.projectPrefix }}/managed-by: {{ .Release.Service }}
{{ .Values.projectPrefix }}/infrastructure-provider: openstack
{{- end -}}

{{/*
Selector labels for cluster-level resources
*/}}
{{- define "openstack-cluster.selectorLabels" -}}
{{ .Values.projectPrefix }}/cluster: {{ include "openstack-cluster.clusterName" . }}
{{- end -}}

{{/*
Labels for cluster-level resources
*/}}
{{- define "openstack-cluster.labels" -}}
{{ include "openstack-cluster.commonLabels" . }}
{{ include "openstack-cluster.selectorLabels" . }}
{{- end -}}

{{/*
Selector labels for component-level resources
*/}}
{{- define "openstack-cluster.componentSelectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $componentName := index . 1 -}}
{{ include "openstack-cluster.selectorLabels" $ctx }}
{{ $ctx.Values.projectPrefix }}/component: {{ $componentName }}
{{- end -}}

{{/*
Labels for component-level resources
*/}}
{{- define "openstack-cluster.componentLabels" -}}
{{ include "openstack-cluster.commonLabels" (index . 0) }}
{{ include "openstack-cluster.componentSelectorLabels" . }}
{{- end -}}

{{/*
Name of the secret containing the cloud credentials.
*/}}
{{- define "openstack-cluster.cloudCredentialsSecretName" -}}
{{- if .Values.cloudCredentialsSecretName -}}
{{- .Values.cloudCredentialsSecretName -}}
{{- else -}}
{{ include "openstack-cluster.componentName" (list . "cloud-credentials") -}}
{{- end -}}
{{- end -}}

{{/*
Outputs the content for a containerd registry file containing mirror configuration.
*/}}
{{- define "openstack-cluster.registryFile" -}}
{{- $registry := index . 0 -}}
{{- $registrySpec := index . 1 -}}
{{-
  $defaultUpstream :=
    eq $registry "docker.io" |
    ternary "registry-1.docker.io" $registry |
    printf "https://%s"
-}}
{{-
  $upstream :=
    kindIs "map" $registrySpec |
    ternary $registrySpec dict |
    dig "upstream" $defaultUpstream
-}}
{{-
  $mirrors :=
    kindIs "map" $registrySpec |
    ternary $registrySpec (dict "mirrors" $registrySpec) |
    dig "mirrors" list
-}}
{{- with $upstream }}
server = "{{ . }}"
{{- end }}
{{- range $mirror := $mirrors }}
{{-
  $url :=
    kindIs "map" $mirror |
    ternary $mirror (dict "url" $mirror) |
    dig "url" "" |
    required "unable to determine mirror url"
}}
{{-
  $capabilities :=
    kindIs "map" $mirror |
    ternary $mirror (dict "capabilities" list) |
    dig "capabilities" list |
    default (list "pull" "resolve")
}}
{{-
  $skipVerify :=
    kindIs "map" $mirror |
    ternary $mirror (dict "skipVerify" false) |
    dig "skipVerify" false
}}
{{-
  $overridePath :=
    kindIs "map" $mirror |
    ternary $mirror (dict "overridePath" true) |
    dig "overridePath" true
}}
[host."{{ $url }}"]
capabilities = [{{ range $i, $cap := $capabilities }}{{ if gt $i 0 }}, {{ end }}"{{ . }}"{{ end }}]
skip_verify = {{ ternary "true" "false" $skipVerify }}
override_path = {{ ternary "true" "false" $overridePath }}
{{- end }}
{{- end }}

{{/*
Produces the spec for a KubeadmConfig object, with support for configuring registry
mirrors and additional packages.
*/}}
{{- define "openstack-cluster.kubeadmConfigSpec" -}}
{{- $ctx := index . 0 }}
{{- $registryMirrors := $ctx.Values.registryMirrors }}
{{- $additionalPackages := $ctx.Values.additionalPackages }}
{{- $trustedCAs := $ctx.Values.trustedCAs }}
{{- $kubeadmConfigSpec := omit (index . 1) "files" "preKubeadmCommands" }}
{{- $files := index . 1 | dig "files" list }}
{{- $preKubeadmCommands := index . 1 | dig "preKubeadmCommands" list }}

{{- with $kubeadmConfigSpec }}
{{- toYaml . }}
{{- end }}
files:
  - path: /etc/containerd/conf.d/.keepdir
    content: |
      # This file is created by the capi-helm-chart to ensure that its parent directory exists
    owner: root:root
    permissions: "0644"
  - path: /etc/containerd/certs.d/.keepdir
    content: |
      # This file is created by the capi-helm-chart to ensure that its parent directory exists
    owner: root:root
    permissions: "0644"
  - path: /etc/containerd/config.toml
    content: |
      [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
    owner: root:root
    permissions: "0644"
    append: true
{{- with $registryMirrors }}
{{- range $registry, $registrySpec := . }}
  - path: /etc/containerd/certs.d/{{ $registry }}/hosts.toml
    content: |
      {{- include "openstack-cluster.registryFile" (list $registry $registrySpec) | nindent 6 }}
    owner: root:root
    permissions: "0644"
{{- end }}
{{- end }}
{{- if $ctx.Values.registryAuth }}
  - path: /etc/containerd/conf.d/auth.toml
    contentFrom:
      secret:
        name: {{ include "openstack-cluster.componentName" (list $ctx "containerd-auth") }}
        key: "auth.toml"
    owner: root:root
    permissions: "0644"
{{- end }}
{{- if $trustedCAs }}
  {{- range $name, $certificate := $trustedCAs }}
  - path: /usr/local/share/ca-certificates/{{ $name }}.crt
    content: |
      {{- nindent 6 $certificate }}
    owner: root:root
    permissions: "0644"
  {{- end }}
{{- end }}
{{- if $files }}
  {{- range $files }}
  - {{ toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- if or $trustedCAs $additionalPackages $preKubeadmCommands }}
preKubeadmCommands:
  {{- if $trustedCAs }}
  - update-ca-certificates
  {{- end }}
  {{- if $additionalPackages }}
  - apt update -y
  - apt install -y {{ join " " $additionalPackages }}
  {{- end }}
  {{- range $preKubeadmCommands }}
  - {{ . }}
  {{- end }}
{{- end }}
{{- end }}
