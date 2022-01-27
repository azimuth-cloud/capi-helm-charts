{{- define "addon.job.uninstall" -}}
{{- $ctx := index . 0 }}
{{- $name := index . 1 }}
{{- $hook := index . 2 }}
{{- $config := index . 3 }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "addon.job.name" (list $ctx $name "uninstall") }}
  labels: {{ include "addon.job.labels" (list $ctx $name "uninstall") | nindent 4 }}
  annotations:
    helm.sh/hook: {{ $hook }}
    helm.sh/hook-weight: {{ $config.uninstallHookWeight | quote }}
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ $config.backoffLimit }}
  activeDeadlineSeconds: {{ $config.activeDeadlineSeconds }}
  template:
    metadata:
      labels: {{ include "addon.job.selectorLabels" (list $ctx $name "uninstall") | nindent 8 }}
    spec:
      {{- with $config.imagePullSecrets }}
      imagePullSecrets: {{ toYaml . | nindent 8 }}
      {{- end }}
      securityContext: {{ toYaml $config.podSecurityContext | nindent 8 }}
      restartPolicy: OnFailure
      serviceAccountName: {{ tpl $config.serviceAccountName $ctx }}
      # Use init containers to do two things before uninstalling
      #
      #   1. Suspend any running install jobs for the addon
      #   2. Install the kubeconfig file from the secret if required
      #
      # We don't use a regular volume for (2) because we need the hook not to block in the
      # case where the secret is not available
      initContainers:
        - name: suspend-install-jobs
          image: {{ printf "%s:%s" $config.image.repository (default $ctx.Chart.AppVersion $config.image.tag) }}
          imagePullPolicy: {{ $config.image.pullPolicy }}
          securityContext: {{ toYaml $config.securityContext | nindent 12 }}
          args:
            - /bin/bash
            - -c
            - |
                set -ex
                {{- $labels := include "addon.job.selectorLabels" (list $ctx $name "install") | fromYaml }}
                {{- range $i, $label := keys $labels -}}
                {{- if $i }}
                LABELS="$LABELS,{{ $label }}={{ index $labels $label }}"
                {{- else }}
                LABELS="{{ $label }}={{ index $labels $label }}"
                {{- end }}
                {{- end }}
                for job in $(kubectl get job -n {{ $ctx.Release.Namespace }} -l "$LABELS" -o name); do
                    kubectl patch $job -n {{ $ctx.Release.Namespace }} -p '{"spec":{"suspend":true}}'
                done
          resources: {{ toYaml $config.resources | nindent 12 }}
        {{- if $config.kubeconfigSecret.name }}
        - name: install-kubeconfig
          image: {{ printf "%s:%s" $config.image.repository (default $ctx.Chart.AppVersion $config.image.tag) }}
          imagePullPolicy: {{ $config.image.pullPolicy }}
          securityContext: {{ toYaml $config.securityContext | nindent 12 }}
          args:
            - /bin/bash
            - -c
            - |
                set -ex
                kubectl_get_secret() {
                    kubectl get secret {{ tpl $config.kubeconfigSecret.name $ctx }} -n {{ $ctx.Release.Namespace }} "$@"
                }
                if kubectl_get_secret; then
                    {{- $template := printf "{{ index .data \"%s\" | base64decode }}" $config.kubeconfigSecret.key }}
                    kubectl_get_secret -o go-template='{{ $template }}' > /config/auth/kubeconfig
                fi
          resources: {{ toYaml $config.resources | nindent 12 }}
          volumeMounts:
            - name: kubeconfig
              mountPath: /config/auth
        {{- end }}
      containers:
        - name: uninstall
          image: {{ printf "%s:%s" $config.image.repository (default $ctx.Chart.AppVersion $config.image.tag) }}
          imagePullPolicy: {{ $config.image.pullPolicy }}
          securityContext: {{ toYaml $config.securityContext | nindent 12 }}
          # We can only make a best effort to delete the addon as we don't want the hook to block
          # So we bail without an error if the kubeconfig doesn't exist or the API is not reachable
          # and we allow the scripts to fail without preventing execution of the following scripts
          args:
            - /bin/bash
            - -c
            - |
                {{- if $config.kubeconfigSecret.name }}
                test -f "$KUBECONFIG" || exit 0
                {{- end }}
                kubectl version || exit 0
                {{- if $config.hooks.preDelete }}
                source ./hook-predelete.sh || true
                {{- end }}
                source ./delete.sh || true
                {{- if $config.hooks.postDelete }}
                source ./hook-postdelete.sh || true
                {{- end }}
          {{- if $config.kubeconfigSecret.name }}
          env:
            - name: KUBECONFIG
              value: /config/auth/kubeconfig
          {{- end }}
          # Set the working directory to the directory containing the config
          workingDir: /config
          resources: {{ toYaml $config.resources | nindent 12 }}
          volumeMounts:
            - name: config
              mountPath: /config
              readOnly: true
            - name: kubeconfig
              mountPath: /config/auth
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
              {{- range $config.extraVolumes }}
              - {{ toYaml . | nindent 16 }}
              {{- end }}
        {{- if $config.kubeconfigSecret.name }}
        - name: kubeconfig
          emptyDir: {}
        {{- end }}
{{- end }}
