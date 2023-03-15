{{- define "cluster-addons.monitoring.pvcManage" -}}
{{- $ctx := index . 0 }}
{{- $namespace := index . 1 }}
{{- $statefulset := index . 2 }}
{{- $pvcSelector := index . 3 }}
{{- $enabled := index . 4 }}
{{- $persistenceEnabled := index . 5 }}
{{- $targetVolumeSize := index . 6 }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "cluster-addons.componentName" (printf "%s-manage-pvcs" $statefulset | list $ctx) }}
  labels: {{ include "cluster-addons.componentLabels" (printf "%s-manage-pvcs" $statefulset | list $ctx) | nindent 4 }}
  annotations:
    helm.sh/hook: pre-upgrade
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ $ctx.Values.hooks.backoffLimit }}
  activeDeadlineSeconds: {{ $ctx.Values.hooks.activeDeadlineSeconds }}
  template:
    metadata:
      labels: {{ include "cluster-addons.componentSelectorLabels" (printf "%s-manage-pvcs" $statefulset | list $ctx) | nindent 8 }}
    spec:
      {{- with $ctx.Values.hooks.imagePullSecrets }}
      imagePullSecrets: {{ toYaml . | nindent 8 }}
      {{- end }}
      securityContext: {{ toYaml $ctx.Values.hooks.podSecurityContext | nindent 8 }}
      restartPolicy: OnFailure
      containers:
        - name: manage-pvcs
          image: {{
            printf "%s:%s"
              $ctx.Values.hooks.image.repository
              (default $ctx.Chart.AppVersion $ctx.Values.hooks.image.tag)
          }}
          imagePullPolicy: {{ $ctx.Values.hooks.image.pullPolicy }}
          securityContext: {{ toYaml $ctx.Values.hooks.securityContext | nindent 12 }}
          args:
            - /bin/bash
            - -c
            - |
                set -ex
                test -f "$KUBECONFIG" || exit 0
                kubectl version || exit 0

                {{- if $enabled }}
                EXISTING_SIZE="$(
                  kubectl get statefulset {{ $statefulset }} \
                    --namespace {{ $namespace }} \
                    --ignore-not-found \
                    --output jsonpath='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}'
                )"
                if [ "$EXISTING_SIZE" != "{{ $targetVolumeSize }}" ]; then
                  kubectl delete statefulset {{ $statefulset }} \
                    --namespace {{ $namespace }} \
                    --ignore-not-found
                fi
                {{- end }}

                {{- if and $enabled $persistenceEnabled }}
                pvcs=($(kubectl get pvc --namespace {{ $namespace }} --selector {{ $pvcSelector }} --output name))
                for pvc in "${pvcs[@]}"; do
                  kubectl patch $pvc \
                    --namespace {{ $namespace }} \
                    --patch '{"spec": {"resources": {"requests": {"storage": "{{ $targetVolumeSize }}"}}}}'
                done
                {{- else }}
                kubectl delete pvc --namespace {{ $namespace }} --selector {{ $pvcSelector }} --wait=false
                {{- end }}
          env:
            - name: KUBECONFIG
              value: /etc/kubernetes/config
          resources: {{ toYaml $ctx.Values.hooks.resources | nindent 12 }}
          volumeMounts:
            - name: etc-kubernetes
              mountPath: /etc/kubernetes
              readOnly: true
      hostNetwork: {{ $ctx.Values.hooks.hostNetwork }}
      {{- with $ctx.Values.hooks.nodeSelector }}
      nodeSelector: {{ toYaml . | nindent 8 }}
      {{- end }}
      {{- with $ctx.Values.hooks.affinity }}
      affinity: {{ toYaml . | nindent 8 }}
      {{- end }}
      {{- with $ctx.Values.hooks.tolerations }}
      tolerations: {{ toYaml . | nindent 8 }}
      {{- end }}
      volumes:
        - name: etc-kubernetes
          secret:
            secretName: {{ include "cluster-addons.componentName" (list $ctx "kubeconfig") }}
            items:
              - key: value
                path: config
{{- end }}
