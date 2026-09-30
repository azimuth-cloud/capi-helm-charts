{{/*
Convert a copy of the merged bootstrap spec after calculating template checksums.
Match CAPI v1.14.2's conversion from v1beta1 to v1beta2.
*/}}
{{- define "openstack-cluster.v1beta2.args" -}}
{{- $args := list -}}
{{- if kindIs "map" . -}}
{{- range $name := keys . | sortAlpha -}}
{{- $value := index $ $name -}}
{{- if not (kindIs "string" $value) -}}
{{- fail (printf "kubeadm argument %s must have a string value" $name) -}}
{{- end -}}
{{- $args = append $args (dict "name" $name "value" $value) -}}
{{- end -}}
{{- else if kindIs "slice" . -}}
{{- $args = deepCopy . -}}
{{- else if . -}}
{{- fail "kubeadm arguments must be a map or a list of name/value objects" -}}
{{- end -}}
{{- toYaml $args -}}
{{- end -}}

{{/* Omit null fields to match CAPI's conversion. */}}
{{- define "openstack-cluster.v1beta2.omitNulls" -}}
{{- if kindIs "map" . -}}
{{- range $key, $value := . -}}
{{- if kindIs "invalid" $value -}}
{{- $_ := unset $ $key -}}
{{- else -}}
{{- include "openstack-cluster.v1beta2.omitNulls" $value -}}
{{- end -}}
{{- end -}}
{{- else if kindIs "slice" . -}}
{{- range . -}}{{- include "openstack-cluster.v1beta2.omitNulls" . -}}{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Omit empty objects and lists, except taints and controlPlane.
An empty taints list disables default taints.
Empty controlPlane selects a control-plane join.
Empty extraEnvs is invalid in v1beta2.
CAPI's PrepareKubeadmConfigsForDiff also removes it before comparing configs for rollout.
*/}}
{{- define "openstack-cluster.v1beta2.omitEmptyObjects" -}}
{{- if kindIs "map" . -}}
{{- range $key, $value := . -}}
{{- include "openstack-cluster.v1beta2.omitEmptyObjects" $value -}}
{{- if or (and (kindIs "map" $value) (empty $value) (ne $key "controlPlane")) (and (kindIs "slice" $value) (empty $value) (ne $key "taints")) -}}
{{- $_ := unset $ $key -}}
{{- end -}}
{{- end -}}
{{- else if kindIs "slice" . -}}
{{- range . -}}{{- include "openstack-cluster.v1beta2.omitEmptyObjects" . -}}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "openstack-cluster.v1beta2.kubeadmConfigSpec" -}}
{{- $spec := deepCopy . -}}
{{- include "openstack-cluster.v1beta2.omitNulls" $spec -}}
{{- $_ := unset $spec "useExperimentalRetryJoin" -}}
{{- $cluster := get $spec "clusterConfiguration" | default dict -}}
{{/* CAPI manages these fields and removes them during conversion. */}}
{{- range $key := list "apiVersion" "kind" "networking" "kubernetesVersion" "clusterName" -}}
{{- $_ := unset $cluster $key -}}
{{- end -}}
{{- $apiServer := get $cluster "apiServer" | default dict -}}
{{- $controlPlaneTimeout := get $apiServer "timeoutForControlPlane" -}}
{{- $_ := unset $apiServer "timeoutForControlPlane" -}}
{{- $components := list (get $cluster "apiServer") (get $cluster "controllerManager") (get $cluster "scheduler") -}}
{{- range append $components (dig "etcd" "local" dict $cluster) -}}
{{- with . -}}
{{- if .extraArgs -}}
{{- $_ := set . "extraArgs" (include "openstack-cluster.v1beta2.args" .extraArgs | fromYamlArray) -}}
{{- else -}}
{{- $_ := unset . "extraArgs" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{/* CAPI omits readOnly when false. */}}
{{- range $components -}}
{{- with . -}}
{{- range .extraVolumes -}}
{{- if not .readOnly -}}{{- $_ := unset . "readOnly" -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- range $phase := list "initConfiguration" "joinConfiguration" -}}
{{- $config := get $spec $phase | default dict -}}
{{- $_ := unset $config "apiVersion" -}}
{{- $_ := unset $config "kind" -}}
{{- $endpoint := get $config "localAPIEndpoint" | default dict -}}
{{- if eq $phase "joinConfiguration" -}}
{{- $endpoint = dig "controlPlane" "localAPIEndpoint" dict $config -}}
{{- end -}}
{{- if not $endpoint.bindPort -}}{{- $_ := unset $endpoint "bindPort" -}}{{- end -}}
{{- if eq (get $endpoint "advertiseAddress") "" -}}{{- $_ := unset $endpoint "advertiseAddress" -}}{{- end -}}
{{- with get $config "nodeRegistration" -}}
{{- if .kubeletExtraArgs -}}
{{- $_ := set . "kubeletExtraArgs" (include "openstack-cluster.v1beta2.args" .kubeletExtraArgs | fromYamlArray) -}}
{{- else -}}
{{- $_ := unset . "kubeletExtraArgs" -}}
{{- end -}}
{{- end -}}
{{- if $controlPlaneTimeout -}}
{{- $timeouts := get $config "timeouts" | default dict -}}
{{- $_ := set $timeouts "controlPlaneComponentHealthCheckSeconds" (include "openstack-cluster.v1beta2.durationSeconds" $controlPlaneTimeout | int) -}}
{{- $_ := set $config "timeouts" $timeouts -}}
{{- $_ := set $spec $phase $config -}}
{{- end -}}
{{- end -}}
{{- with get $spec "initConfiguration" -}}
{{- range .bootstrapTokens -}}
{{- if hasKey . "ttl" -}}
{{- $_ := set . "ttlSeconds" (include "openstack-cluster.v1beta2.durationSeconds" .ttl | int) -}}
{{- $_ := unset . "ttl" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- with get $spec "joinConfiguration" -}}
{{- $join := . -}}
{{- with get . "discovery" -}}
{{- if hasKey . "timeout" -}}
{{- $timeouts := get $join "timeouts" | default dict -}}
{{- $_ := set $timeouts "tlsBootstrapSeconds" (include "openstack-cluster.v1beta2.durationSeconds" .timeout | int) -}}
{{- $_ := set $join "timeouts" $timeouts -}}
{{- $_ := unset . "timeout" -}}
{{- end -}}
{{- with .bootstrapToken -}}
{{- if not .unsafeSkipCAVerification -}}{{- $_ := unset . "unsafeSkipCAVerification" -}}{{- end -}}
{{- end -}}
{{- with dig "file" "kubeConfig" dict . -}}
{{- with .cluster -}}
{{- if not .insecureSkipTLSVerify -}}{{- $_ := unset . "insecureSkipTLSVerify" -}}{{- end -}}
{{- end -}}
{{- with dig "user" "exec" dict . -}}
{{- if not .provideClusterInfo -}}{{- $_ := unset . "provideClusterInfo" -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- range $spec.files -}}
{{- if not .append -}}{{- $_ := unset . "append" -}}{{- end -}}
{{- $file := . -}}
{{- range $key := list "content" "owner" "permissions" "encoding" "contentFormat" -}}
{{- if eq (get $file $key) "" -}}{{- $_ := unset $file $key -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- with dig "ignition" "containerLinuxConfig" dict $spec -}}
{{- if not .strict -}}{{- $_ := unset . "strict" -}}{{- end -}}
{{- if eq (get . "additionalConfig") "" -}}{{- $_ := unset . "additionalConfig" -}}{{- end -}}
{{- end -}}
{{- include "openstack-cluster.v1beta2.omitEmptyObjects" $spec -}}
{{- toYaml $spec -}}
{{- end -}}

{{- define "openstack-cluster.v1beta2.controlPlaneRemediation" -}}
{{- $remediation := deepCopy . -}}
{{- include "openstack-cluster.v1beta2.omitNulls" $remediation -}}
{{- range $key := list "retryPeriod" "minHealthyPeriod" -}}
{{- if hasKey $remediation $key -}}
{{- $_ := set $remediation (printf "%sSeconds" $key) (include "openstack-cluster.v1beta2.durationSeconds" (get $remediation $key) | int) -}}
{{/* CAPI omits retryPeriod when its old value was zero. */}}
{{- if and (eq $key "retryPeriod") (not (regexMatch "[1-9]" (toString (get $remediation $key)))) -}}
{{- $_ := unset $remediation "retryPeriodSeconds" -}}
{{- end -}}
{{- $_ := unset $remediation $key -}}
{{- end -}}
{{- end -}}
{{- toYaml $remediation -}}
{{- end -}}
