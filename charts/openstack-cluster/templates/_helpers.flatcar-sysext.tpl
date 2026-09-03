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

# Note that additionalConfig below is CLC and NOT butane. This is because CAPI only supports ignitionv2
# at the moment.

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
          # Flatcar ships docker/containerd sysexts enabled by default
          # Disable this as per https://www.flatcar.org/docs/latest/sys-ext/#remove-docker-and--or-containerd-from-flatcar
          # So that we manage containerd outselves
          - path: /etc/extensions/docker-flatcar.raw
            target: /dev/null
            overwrite: true
            hard: false
          - path: /etc/extensions/containerd-flatcar.raw
            target: /dev/null
            overwrite: true
            hard: false
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
        # this service must not run if no key has been provided by openstack, it retries
        # forever causing a mount error in the kernel log.
        # sshkeys.service (baked into flatcar) starts this unit directly via `systemctl start`
        # whenever it isn't already masked, regardless of enabled/disabled, so when there is
        # no key the service must be masked.
        - name: coreos-metadata-sshkeys@core.service
          {{- if $ctx.Values.machineSSHKeyName }}
          enabled: true
          {{- else }}
          mask: true
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

        {{- if dig "disableAutologin" true ($ctx.Values.flatcar | default dict) }}
        # flatcar enables auto-login to the console (core user, which has paswordless sudo) by
        # default. Disable this.
        # https://www.flatcar.org/docs/latest/os-config/host-config/other-settings/?highlight=autologin#adding-custom-kernel-boot-options
        - name: getty@.service
          dropins:
            - name: 10-autologin.conf
              contents: |
                [Service]
                ExecStart=
                ExecStart=-/sbin/agetty --noclear %I $TERM
        {{- end }}
{{- end }}
