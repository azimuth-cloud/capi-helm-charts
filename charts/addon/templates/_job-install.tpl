{{/*
  In order to only run jobs when something has changed, we include a fragment of
  the checksum of the job spec in the job name. The pod template contains the
  checksum of the configuration as an annotation, so that the job spec changes when
  the configuration does.

  Most elements of the job spec are immutable, so this guarantees we get new jobs
  at the right times. Job labels are OK to update, and we include the revision there
  in order to be able to order the jobs in time.
*/}}
{{- define "addon.job.install.spec" -}}
{{- $ctx := index . 0 -}}
{{- $name := index . 1 -}}
{{- $config := index . 2 -}}
backoffLimit: {{ $config.backoffLimit }}
activeDeadlineSeconds: {{ $config.activeDeadlineSeconds }}
template:
  metadata:
    labels: {{ include "addon.job.selectorLabels" (list $ctx $name "install") | nindent 6 }}
    annotations:
      capi.stackhpc.com/config-checksum: {{ include "addon.config.secret" . | sha256sum }}
  spec:
    {{- with $config.imagePullSecrets }}
    imagePullSecrets: {{ toYaml . | nindent 6 }}
    {{- end }}
    securityContext: {{ toYaml $config.podSecurityContext | nindent 6 }}
    restartPolicy: OnFailure
    {{- if not $config.kubeconfigSecret.name }}
    serviceAccountName: {{ tpl $config.serviceAccountName $ctx }}
    {{- end }}
    containers:
      - name: install
        image: {{ printf "%s:%s" $config.image.repository (default $ctx.Chart.AppVersion $config.image.tag) }}
        imagePullPolicy: {{ $config.image.pullPolicy }}
        securityContext: {{ toYaml $config.securityContext | nindent 10 }}
        args:
          - /bin/bash
          - -c
          - |
              set -exo pipefail
              {{- if $config.hooks.preInstall }}
              source ./hook-preinstall.sh
              {{- end }}
              source ./install.sh
              {{- if $config.hooks.postInstall }}
              source ./hook-postinstall.sh
              {{- end }}
        {{- if $config.kubeconfigSecret.name }}
        env:
          - name: KUBECONFIG
            value: /config/kubeconfig
        {{- end }}
        # Set the working directory to the directory containing the config
        workingDir: /config
        resources: {{ toYaml $config.resources | nindent 10 }}
        volumeMounts:
          - name: config
            mountPath: /config
            readOnly: true
    hostNetwork: {{ $config.hostNetwork }}
    {{- with $config.nodeSelector }}
    nodeSelector: {{ toYaml . | nindent 6 }}
    {{- end }}
    {{- with $config.affinity }}
    affinity: {{ toYaml . | nindent 6 }}
    {{- end }}
    {{- with $config.tolerations }}
    tolerations: {{ toYaml . | nindent 6 }}
    {{- end }}
    volumes:
      - name: config
        projected:
          sources:
            - secret:
                name: {{ include "addon.fullname" (list $ctx $name) }}-config
            {{- if $config.kubeconfigSecret.name }}
            - secret:
                name: {{ tpl $config.kubeconfigSecret.name $ctx }}
                items:
                  - key: {{ $config.kubeconfigSecret.key }}
                    path: kubeconfig
            {{- end }}
            {{- range $config.extraVolumes }}
            - {{ toYaml . | nindent 14 }}
            {{- end }}
{{- end }}

{{- define "addon.job.install" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
apiVersion: batch/v1
kind: Job
metadata:
  {{- $checksum := include "addon.job.install.spec" . | sha256sum }}
  name: {{ include "addon.job.name" (list $ctx $name "install") }}-{{ trunc 8 $checksum }}
  labels: {{ include "addon.job.labels" (list $ctx $name "install") | nindent 4 }}
spec: {{ include "addon.job.install.spec" . | nindent 2 }}
{{- end }}
