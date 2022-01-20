{{- define "addon.job.install" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
{{- $config := index . 2 }}
apiVersion: batch/v1
kind: Job
metadata:
  {{- $configChecksum := include "addon.config.secret" . | sha256sum }}
  name: {{ include "addon.job.name" (list $ctx $name "install") }}-{{ trunc 8 $configChecksum }}
  labels: {{ include "addon.job.labels" (list $ctx $name "install") | nindent 4 }}
spec:
  backoffLimit: {{ $config.backoffLimit }}
  activeDeadlineSeconds: {{ $config.activeDeadlineSeconds }}
  template:
    metadata:
      labels: {{ include "addon.job.selectorLabels" (list $ctx $name "install") | nindent 8 }}
    spec:
      {{- with $config.imagePullSecrets }}
      imagePullSecrets: {{ toYaml . | nindent 8 }}
      {{- end }}
      securityContext: {{ toYaml $config.podSecurityContext | nindent 8 }}
      restartPolicy: OnFailure
      {{- if not $config.kubeconfigSecret.name }}
      serviceAccountName: {{ tpl $config.serviceAccountName $ctx }}
      {{- end }}
      containers:
        - name: install
          image: {{ printf "%s:%s" $config.image.repository (default $ctx.Chart.AppVersion $config.image.tag) }}
          imagePullPolicy: {{ $config.image.pullPolicy }}
          securityContext: {{ toYaml $config.securityContext | nindent 12 }}
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
          resources: {{ toYaml $config.resources | nindent 12 }}
          volumeMounts:
            - name: config
              mountPath: /config
              readOnly: true
      hostNetwork: {{ $config.hostNetwork }}
      {{- with $config.nodeSelector }}
      nodeSelector: {{ toYaml . | nindent 8 }}
      {{- end }}
      {{- with $config.affinity }}
      affinity: {{ toYaml . | nindent 8 }}
      {{- end }}
      {{- with $config.tolerations }}
      tolerations: {{ toYaml . | nindent 8 }}
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
              - {{ toYaml . | nindent 16 }}
              {{- end }}
{{- end }}
