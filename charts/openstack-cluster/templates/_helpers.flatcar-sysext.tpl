{{/*
Helpers for the flatcar-sysext osDistro variant.
*/}}

{{/*
Splits a sysext checksum value into the {function, sum} pair.
Only sha512 checksums are supported by ignition, even though
other ones are allowed by the schema.
*/}}
{{- define "openstack-cluster.flatcar.checksumParts" -}}
{{- if not (hasPrefix "sha512-" .) -}}
{{- fail (printf "sysext checksum %q must be in the form \"sha512-<hex>\" - Ignition only supports sha512 verification hashes" .) -}}
{{- end -}}
function: sha512
sum: {{ trimPrefix "sha512-" . }}
{{- end }}

{{/*
Produces the spec for an Ignition based OS specific KubeadmConfig object.
Conditional on osDistro set to "flatcar-sysext".

Ignition downloads the sysexts declared in storage.files synchronously before any systemd service starts,
so the extensions are already in place when systemd-sysext activates them during normal boot.

${COREOS_OPENSTACK_HOSTNAME} and ${COREOS_OPENSTACK_INSTANCE_UUID} are set by coreos-metadata
(EnvironmentFile=/run/metadata/flatcar), exported in preKubeadmCommands, then substituted into
/etc/kubeadm.yml by envsubst before kubeadm runs.
*/}}
{{- define "openstack-cluster.flatcarSysextKubeadmConfigSpec" -}}
{{- $ctx := index . 0 }}
{{- $sysexts := index . 1 }}
{{- if not (hasKey $sysexts "kubernetes") }}
{{- fail "flatcar.sysexts.kubernetes is required when osDistro=flatcar-sysext - it provides the kubeadm/kubelet binaries" }}
{{- end }}
{{- if not (hasKey $sysexts "containerd") }}
{{- fail "flatcar.sysexts.containerd is required when osDistro=flatcar-sysext" }}
{{- end }}
initConfiguration:
  nodeRegistration:
    name: ${COREOS_OPENSTACK_HOSTNAME}
    kubeletExtraArgs:
      cloud-provider: external
      provider-id: "openstack:///${COREOS_OPENSTACK_INSTANCE_UUID}"
joinConfiguration:
  nodeRegistration:
    name: ${COREOS_OPENSTACK_HOSTNAME}
    kubeletExtraArgs:
      cloud-provider: external
      provider-id: "openstack:///${COREOS_OPENSTACK_INSTANCE_UUID}"
preKubeadmCommands:
  - export COREOS_OPENSTACK_HOSTNAME=${COREOS_OPENSTACK_HOSTNAME%.*}
  - envsubst < /etc/kubeadm.yml > /etc/kubeadm.yml.tmp
  - mv /etc/kubeadm.yml.tmp /etc/kubeadm.yml
format: ignition
ignition:
  containerLinuxConfig:
    additionalConfig: |
      storage:
        files:
        {{- range $name, $sysext := $sysexts }}
        {{- $checksum := include "openstack-cluster.flatcar.checksumParts" (required (printf "flatcar.sysexts.%s.checksum is required when osDistro=flatcar-sysext" $name) $sysext.checksum) | fromYaml }}
          - path: /opt/extensions/{{ $name }}/{{ $name }}.raw
            contents:
              remote:
                url: "{{ required (printf "flatcar.sysexts.%s.url is required when osDistro=flatcar-sysext" $name) $sysext.url }}"
                verification:
                  hash:
                    function: {{ $checksum.function }}
                    sum: {{ $checksum.sum }}
            mode: 0644
        {{- end }}
        links:
        {{- range $name, $sysext := $sysexts }}
          - target: /opt/extensions/{{ $name }}/{{ $name }}.raw
            path: /etc/extensions/{{ $name }}.raw
            hard: false
        {{- end }}
      systemd:
        units:
        # Disabling auto-update
        - name: update-engine.service
          mask: true
        - name: locksmithd.service
          mask: true
        - name: systemd-sysupdate.timer
          enabled: false

        # Kubernetes-focused units
        {{- if $ctx.Values.machineSSHKeyName }}
        - name: coreos-metadata-sshkeys@.service
          enabled: true
        {{- end }}
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
