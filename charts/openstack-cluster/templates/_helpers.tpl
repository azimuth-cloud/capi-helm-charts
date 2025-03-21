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
Outputs the node registration object for setting node labels.
*/}}
{{- define "openstack-cluster.nodeRegistration.nodeLabels" -}}
nodeRegistration:
  kubeletExtraArgs:
    node-labels: "{{ range $i, $k := (keys . | sortAlpha) }}{{ if ne $i 0 }},{{ end }}{{ $k }}={{ index $ $k }}{{ end }}"
{{- end }}

{{/*
Converts the tags in a Neutron filter when required.
*/}}
{{- define "openstack-cluster.convert.tags" -}}
{{- if kindIs "string" . -}}
{{- splitList "," . | toYaml }}
{{- else -}}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Converts a v1alpha7 Neutron ports filter to a v1beta1 filter.
*/}}
{{- define "openstack-cluster.convert.neutronPortsFilter" -}}
{{- $ports := list -}}
{{- range $p := . -}}
{{- if $p.network -}}
{{- with $p.network -}}
{{- if not ( hasKey . "filter" ) -}}
{{- $portNetwork := include "openstack-cluster.convert.neutronFilter" . | fromYaml -}}
{{- $p := set $p "network" $portNetwork -}}
{{- end -}}
{{- $ports = append $ports $p -}}
{{- end -}}
{{- else -}}
{{- $ports = append $ports $p -}}
{{- end -}}
{{- end -}}
{{- toYaml $ports }}
{{- end }}

{{/*
Converts a v1alpha7 Neutron filter to a v1beta1 filter.
*/}}
{{- define "openstack-cluster.convert.neutronFilter" -}}
{{- if hasKey . "id" -}}
id: {{ .id }}
{{- else -}}
filter:
  {{- with omit . "tags" "tagsAny" "notTags" "notTagsAny" }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  {{- with .tags }}
  tags: {{ include "openstack-cluster.convert.tags" . | nindent 4 }}
  {{- end }}
  {{- with .tagsAny }}
  tagsAny: {{ include "openstack-cluster.convert.tags" . | nindent 4 }}
  {{- end }}
  {{- with .notTags }}
  notTags: {{ include "openstack-cluster.convert.tags" . | nindent 4 }}
  {{- end }}
  {{- with .notTagsAny }}
  notTagsAny: {{ include "openstack-cluster.convert.tags" . | nindent 4 }}
  {{- end }}
{{- end }}
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
{{- if ne .Values.osDistro "flatcar" }}
preKubeadmCommands:
  - |
      /usr/bin/bash -s <<EOF
      grep -q '\[plugins."io.containerd.grpc.v1.cri".registry\]' /etc/containerd/config.toml && exit
      cat <<CONTENT >> /etc/containerd/config.toml
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
      CONTENT
      systemctl restart containerd
      EOF
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

{{/*
Produces the spec for an Ignition based OS specific KubeadmConfig object conditional on osDistro set to "flatcar".
*/}}
{{- define "openstack-cluster.flatcarKubeadmConfigSpec" -}}
initConfiguration:
  nodeRegistration:
    name: ${COREOS_OPENSTACK_HOSTNAME}
joinConfiguration:
  nodeRegistration:
    name: ${COREOS_OPENSTACK_HOSTNAME}
preKubeadmCommands:
  - export COREOS_OPENSTACK_HOSTNAME=${COREOS_OPENSTACK_HOSTNAME%.*}
  - envsubst < /etc/kubeadm.yml > /etc/kubeadm.yml.tmp
  - mv /etc/kubeadm.yml.tmp /etc/kubeadm.yml
format: ignition
ignition:
  containerLinuxConfig:
    additionalConfig: |
      systemd:
        units:
        - name: coreos-metadata-sshkeys@.service
          enabled: true
        - name: kubeadm.service
          enabled: true
          dropins:
          - name: 10-flatcar.conf
            contents: |
              [Unit]
              Requires=containerd.service coreos-metadata.service
              After=containerd.service coreos-metadata.service
              [Service]
              EnvironmentFile=/run/metadata/flatcar
{{- end }}

{{- define "openstack-cluster.osDistroKubeadmConfigSpec" }}
{{- $ctx := index . 0 }}
{{- $osDistro := $ctx.Values.osDistro }}
{{- if eq $osDistro "flatcar" }}
{{- include "openstack-cluster.flatcarKubeadmConfigSpec" $ctx }}
{{- end }}
{{- end }}

{{/*
Create folders necessary for webhook integration.
*/}}
{{- define "openstack-cluster.webhookPatches" }}
  preKubeadmCommands:
    - mkdir -p /etc/kubernetes/webhooks
    - mkdir -p /etc/kubernetes/patches
{{- end }}

{{/*
Supplement kubeadmConfig with apiServer config and webhook patches as needed. Authentication
webhooks and policies for audit logging can be added here.
*/}}
{{- define "openstack-cluster.patchConfigSpec" -}}
{{- $ctx := index . 0 }}
{{- $authWebhook := $ctx.Values.authWebhook }}
  clusterConfiguration:
    apiServer:
      extraArgs:
{{- if $authWebhook }}
        authorization-mode: Node,Webhook,RBAC
{{- if eq $authWebhook "k8s-keystone-auth" }}
        authentication-token-webhook-config-file: /etc/kubernetes/webhooks/keystone_webhook_config.yaml
        authorization-webhook-config-file: /etc/kubernetes/webhooks/keystone_webhook_config.yaml
{{/*
Add else if blocks with other webhooks and apiServer arguments (i.e. audit logging) 
in future
*/}}
{{- end }}
  initConfiguration:
    patches:
      directory: /etc/kubernetes/patches
  joinConfiguration:
    patches:
      directory: /etc/kubernetes/patches
{{- include "openstack-cluster.webhookPatches" $ctx }}
{{- if eq $authWebhook "k8s-keystone-auth" }}
{{- include "openstack-cluster.k8sKeystoneAuthWebhook" $ctx }}
{{/*
Add else if blocks with other webhooks or policy files in future.
*/}}
{{- end }}
{{- end }}
{{- end }}

{{/*
Produces integration for k8s-keystone-auth webhook on apiserver
*/}}
{{- define "openstack-cluster.k8sKeystoneAuthWebhook" }}
  files:
    - path: /etc/kubernetes/patches/kube-apiserver0+strategic.yaml
      permissions: "0644"
      owner: root:root
      content: |
        spec:
          containers:
          -  name: kube-apiserver
             volumeMounts:
             - mountPath: /etc/kubernetes/webhooks
               name: kube-webhooks
               readOnly: true
          volumes:
          - hostPath:
              path: /etc/kubernetes/webhooks
              type: DirectoryOrCreate
            name: kube-webhooks
    - path: /etc/kubernetes/webhooks/keystone_webhook_config.yaml
      content: |
        ---
        apiVersion: v1
        kind: Config
        preferences: {}
        clusters:
          - cluster:
              insecure-skip-tls-verify: true
              server: https://127.0.0.1:8443/webhook
            name: webhook
        users:
          - name: webhook
        contexts:
          - context:
              cluster: webhook
              user: webhook
            name: webhook
        current-context: webhook
      owner: root:root
      permissions: "0644"
{{- end }}
