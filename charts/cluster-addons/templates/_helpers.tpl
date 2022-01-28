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
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
{{- with $ctx.Values.jobDefaults }}
{{- toYaml . }}
{{- end }}
{{- if $ctx.Values.kubeconfigSecret.name }}
kubeconfigSecret:
  name: {{ tpl $ctx.Values.kubeconfigSecret.name $ctx }}
  {{- with $ctx.Values.kubeconfigSecret.key }}
  key: {{ . }}
  {{- end }}
{{- end }}
serviceAccountName: {{ tpl $ctx.Values.serviceAccount.name $ctx }}
enabled: {{ include "cluster-addons.enabled" . }}
dependsOn: {{
  (include "cluster-addons.dependsOn.enabled" . | fromYaml).value |
    default list |
    toYaml |
    nindent 2
}}
uninstallHookWeight: {{ include "cluster-addons.uninstallHookWeight" . }}
{{- if and $ctx.Values.clusterApi (not (has $name $ctx.Values.categories.bootstrap)) }}
extraInitContainers:
  - name: wait-for-capi-cluster
    image: {{
      printf "%s:%s"
        $ctx.Values.jobDefaults.image.repository
        (default $ctx.Chart.AppVersion $ctx.Values.jobDefaults.image.tag)
    }}
    imagePullPolicy: {{ $ctx.Values.jobDefaults.image.pullPolicy }}
    securityContext: {{ toYaml $ctx.Values.jobDefaults.securityContext | nindent 6 }}
    args:
      - kubectl
      - wait
      - --for=condition=Ready
      - clusters.cluster.x-k8s.io
      - {{ tpl $ctx.Values.clusterName $ctx }}
      - --namespace
      - {{ $ctx.Release.Namespace }}
      - --timeout
      - "-1s"
    resources: {{ toYaml $ctx.Values.jobDefaults.resources | nindent 6 }}
{{- end }}
{{- end }}

{{/*
Determines if an addon is enabled given the name.
*/}}
{{- define "cluster-addons.enabled" -}}
{{- $ctx := index . 0 -}}
{{- $name := index . 1 -}}
{{- if eq $name "ccm-openstack" -}}
{{- and $ctx.Values.openstack.enabled $ctx.Values.openstack.ccm.enabled | toYaml -}}
{{- else if eq $name "cert-manager" -}}
{{- $ctx.Values.certManager.enabled | toYaml -}}
{{- else if eq $name "cloud-config" -}}
{{- $ctx.Values.openstack.enabled | toYaml -}}
{{- else if eq $name "cni-calico" -}}
{{- and $ctx.Values.cni.enabled (eq $ctx.Values.cni.type "calico") | toYaml -}}
{{- else if eq $name "cni-cilium" -}}
{{- and $ctx.Values.cni.enabled (eq $ctx.Values.cni.type "cilium") | toYaml -}}
{{- else if eq $name "csi-cinder" -}}
{{- and $ctx.Values.openstack.enabled $ctx.Values.openstack.csiCinder.enabled | toYaml -}}
{{- else if eq $name "ingress-nginx" -}}
{{- and $ctx.Values.ingress.enabled $ctx.Values.ingress.nginx.enabled | toYaml -}}
{{- else if eq $name "metrics-server" -}}
{{- $ctx.Values.metricsServer.enabled | toYaml -}}
{{- else if eq $name "monitoring" -}}
{{- $ctx.Values.monitoring.enabled | toYaml -}}
{{- else if hasKey $ctx.Values.extraAddons $name -}}
{{- dig $name "enabled" true $ctx.Values.extraAddons | toYaml -}}
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
Produces the explicit dependencies for an addon.

The result is returned as an object so it can be used with fromYaml.
*/}}
{{- define "cluster-addons.dependsOn.explicit" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
value:
  {{- if (list "ccm-openstack" "csi-cinder" | has $name) }}
  - cloud-config
  {{- else if eq $name "monitoring" }}
  - storage
  - ingress
  {{- else if hasKey $ctx.Values.extraAddons $name }}
  {{- dig $name "dependsOn" list $ctx.Values.extraAddons | toYaml | nindent 2 }}
  {{- else }}
  []
  {{- end }}
{{- end }}

{{/*
Produces the dependencies for an addon, resolving any categories and including the
bootstrap addons as an implicit dependency (unless the addon itself is a bootstrap
addon).

The result is returned as an object so it can be used with fromYaml.
*/}}
{{- define "cluster-addons.dependsOn.all" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
{{- $categories := $ctx.Values.categories }}
{{- $explicit := (include "cluster-addons.dependsOn.explicit" . | fromYaml).value | default list }}
value:
  {{- if not (has $name $categories.bootstrap) }}
  {{- range $categories.bootstrap }}
  - {{ . }}
  {{- end }}
  {{- end }}
  {{- range $explicit }}
  {{- if hasKey $categories . }}
  {{- range (dig . list $categories) }}
  - {{ . }}
  {{- end }}
  {{- else }}
  - {{ . }}
  {{- end }}
  {{- end }}
{{- end }}

{{/*
Produces the dependencies for an addon, ensuring uniqueness and a consistent ordering
and only including those that are enabled.

The result is returned as an object so it can be used with fromYaml.
*/}}
{{- define "cluster-addons.dependsOn.enabled" -}}
{{- $ctx := index . 0 }}
{{-
  $sortedUnique := (include "cluster-addons.dependsOn.all" . | fromYaml).value |
    default list |
    uniq |
    sortAlpha
}}
value:
  {{- range $sortedUnique }}
  {{- if eq (include "cluster-addons.enabled" (list $ctx .)) "true" }}
  - {{ . }}
  {{- end }}
  {{- end }}
{{- end }}

{{/*
Produces the uninstall hook weight for the specified addon, ensuring that it is
removed before any of its dependencies. Only addons that are enabled are considered.

Addons with no enabled dependencies have a weight of zero. Addons with at least one
enabled dependency have a weight that is one less than the minimum of the weights
of the dependencies.
*/}}
{{- define "cluster-addons.uninstallHookWeight" -}}
{{- $ctx := index . 0 -}}
{{- $name := index . 1 -}}
{{- $weight := 1 }}
{{- $enabled := (include "cluster-addons.dependsOn.enabled" . | fromYaml).value | default list -}}
{{- range $enabled -}}
{{- $dependencyWeight := include "cluster-addons.uninstallHookWeight" (list $ctx .) | atoi -}}
{{- $weight = min $weight $dependencyWeight -}}
{{- end -}}
{{- sub $weight 1 -}}
{{- end }}
