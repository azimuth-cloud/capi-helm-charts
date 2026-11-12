{{/*
The complete Job spec is hashed into its name, so script, version, image and
configuration changes do not attempt to modify an immutable Job template.
*/}}
{{- define "cluster-addons.calicoCrdJobSpec" -}}
backoffLimit: 4
activeDeadlineSeconds: 600
template:
  spec:
    serviceAccountName: install-calico-crds
    hostNetwork: true
    # Do not depend on tenant CoreDNS for downloading the upstream manifest.
    dnsPolicy: Default
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
    tolerations:
      - operator: Exists
        effect: NoSchedule
      - operator: Exists
        effect: NoExecute
    restartPolicy: Never
    containers:
      - name: install
        image: {{ .Values.cni.calico.crdImage | quote }}
        imagePullPolicy: IfNotPresent
        command:
          - /bin/sh
          - -ec
          - |-
{{- required "files/install-calico-crds.sh must be packaged in cluster-addons" (.Files.Get "files/install-calico-crds.sh") | nindent 12 }}
        env:
          - name: CALICO_CRD_VERSION
            value: {{ .Values.cni.calico.crdChartVersion | quote }}
{{- end -}}
