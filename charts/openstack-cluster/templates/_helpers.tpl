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
Template that merges two variables with the latter taking precedence and outputs the result as YAML.
Lists are merged by concatenating them rather than overwriting.
*/}}
{{- define "openstack-cluster.mergeConcat" -}}
{{- $left := index . 0 }}
{{- $right := index . 1 }}
{{- if kindIs (kindOf list) $left }}
{{- if kindIs (kindOf list) $right }}
{{ concat $left $right | toYaml }}
{{- else }}
{{ default $left $right | toYaml }}
{{- end }}
{{- else if kindIs (kindOf dict) $left }}
{{- if kindIs (kindOf dict) $right }}
{{- range $key := concat (keys $left) (keys $right) | uniq }}
{{- if and (hasKey $left $key) (hasKey $right $key) }}
{{- $merged := include "openstack-cluster.mergeConcat" (list (index $left $key) (index $right $key)) }}
{{ $key }}: {{ $merged | nindent 2 }}
{{- else if hasKey $left $key }}
{{ index $left $key | dict $key | toYaml }}
{{- else }}
{{ index $right $key | dict $key | toYaml }}
{{- end }}
{{- end }}
{{- else }}
{{ default $left $right | toYaml }}
{{- end }}
{{- else }}
{{ default $left $right | toYaml }}
{{- end }}
{{- end }}

{{/*
Applies a list of templates to an input object sequentially.
*/}}
{{- define "openstack-cluster.mergeConcatMany" -}}
{{- $obj := first . }}
{{- range $overrides := rest . }}
{{- $obj = include "openstack-cluster.mergeConcat" (list $obj $overrides) | fromYaml }}
{{- end }}
{{- toYaml $obj }}
{{- end }}

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
Produces the kubeadmConfigSpec required to configure containerd.
*/}}
{{- define "openstack-cluster.kubeadmConfigSpec.containerd" -}}
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
{{- with .Values.registryMirrors }}
{{- range $registry, $registrySpec := . }}
  - path: /etc/containerd/certs.d/{{ $registry }}/hosts.toml
    content: |
      {{- include "openstack-cluster.registryFile" (list $registry $registrySpec) | nindent 6 }}
    owner: root:root
    permissions: "0644"
{{- end }}
{{- end }}
{{- if .Values.registryAuth }}
  - path: /etc/containerd/conf.d/auth.toml
    contentFrom:
      secret:
        name: {{ include "openstack-cluster.componentName" (list . "containerd-auth") }}
        key: "auth.toml"
    owner: root:root
    permissions: "0644"
{{- end }}
{{- end }}

{{/*
Produces the kubeadmConfigSpec required to configure additional trusted CAs for cluster nodes,
e.g. for private registries.
*/}}
{{- define "openstack-cluster.kubeadmConfigSpec.trustedCAs" -}}
{{- with .Values.trustedCAs }}
files:
  {{- range $name, $certificate := . }}
  - path: /usr/local/share/ca-certificates/{{ $name }}.crt
    content: |
      {{- nindent 6 $certificate }}
    owner: root:root
    permissions: "0644"
  {{- end }}
preKubeadmCommands:
  - update-ca-certificates
{{- end }}
{{- end }}

{{/*
Produces the kubeadmConfigSpec required to install additional packages.
*/}}
{{- define "openstack-cluster.kubeadmConfigSpec.additionalPackages" -}}
{{- with .Values.additionalPackages }}
preKubeadmCommands:
  - apt update -y
  - apt install -y {{ join " " . }}
{{- end }}
{{- end }}

{{/*
Produces the spec for a KubeadmConfig object.
*/}}
{{- define "openstack-cluster.kubeadmConfigSpec" -}}
{{- $ctx := index . 0 }}
{{- $kubeadmConfigSpec := index . 1 }}
{{-
  list
    (include "openstack-cluster.kubeadmConfigSpec.trustedCAs" $ctx | fromYaml)
    (include "openstack-cluster.kubeadmConfigSpec.containerd" $ctx | fromYaml)
    (include "openstack-cluster.kubeadmConfigSpec.additionalPackages" $ctx | fromYaml)
    $kubeadmConfigSpec |
  include "openstack-cluster.mergeConcatMany"
}}
{{- end }}
