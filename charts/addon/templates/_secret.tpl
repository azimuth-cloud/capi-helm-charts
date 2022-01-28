{{- define "addon.config.secret" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
{{- $config := index . 2 }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "addon.fullname" (list $ctx $name) }}-config
  labels: {{ include "addon.labels" (list $ctx $name) | nindent 4 }}
stringData:
  {{- range $filename, $content := $config.extraFiles }}
  {{ $filename }}: |
    {{- $content | nindent 4 }}
  {{- end }}
  {{- with $config.hooks.preInstall }}
  hook-preinstall.sh: |
    {{- tpl . $ctx | nindent 4 }}
  {{- end }}
  {{- with $config.hooks.postInstall }}
  hook-postinstall.sh: |
    {{- tpl . $ctx | nindent 4 }}
  {{- end }}
  {{- with $config.hooks.preDelete }}
  hook-predelete.sh: |
    {{- tpl . $ctx | nindent 4 }}
  {{- end }}
  {{- with $config.hooks.postDelete }}
  hook-postdelete.sh: |
    {{- tpl . $ctx | nindent 4 }}
  {{- end }}
  {{- if eq $config.installType "helm" }}
  values.yaml: |
    {{- include "addon.helm.values" (list $ctx $name $config.helm) | nindent 4 }}
  install.sh: |
    {{- include "addon.helm.install" (list $name $config.helm) | nindent 4 }}
  delete.sh: |
    {{- include "addon.helm.delete" (list $name $config.helm) | nindent 4 }}
  {{- else if eq $config.installType "kustomize" }}
  kustomization.yaml: |
    {{- include "addon.kustomize.kustomization" (list $ctx $name $config.kustomize) | nindent 4 }}
  install.sh: |
    {{- include "addon.kustomize.install" (list $name $config.kustomize) | nindent 4 }}
  delete.sh: |
    {{- include "addon.kustomize.delete" (list $name $config.kustomize) | nindent 4 }}
  {{- else if eq $config.installType "custom" }}
  install.sh: |
    {{-
      tpl (required "custom.install is required for a custom job" $config.custom.install) $ctx |
        nindent 4
    }}
  delete.sh: |
    {{-
      tpl (required "custom.delete is required for a custom job" $config.custom.delete) $ctx |
        nindent 4
    }}
  {{- else }}
  {{- fail (printf "Unrecognised install type '%s'" $config.installType) }}
  {{- end }}
{{- end }}
