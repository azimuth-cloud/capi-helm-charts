{{/*
Match CAPI v1.14.2 ConvertToSeconds: drop fractional seconds and cap positive values at MaxInt32.
Use integer arithmetic to avoid rounding errors.
*/}}
{{- define "openstack-cluster.v1beta2.durationSeconds" -}}
{{- $duration := toString . -}}
{{- if not (regexMatch `^[+-]?(0|(([0-9]+(\.[0-9]*)?|\.[0-9]+)(ns|us|µs|μs|ms|s|m|h))+)$` $duration) -}}
{{- fail (printf "invalid Go duration %q" $duration) -}}
{{- end -}}
{{- $negative := hasPrefix "-" $duration -}}
{{- $unsigned := trimPrefix "+" (trimPrefix "-" $duration) -}}
{{- $seconds := int64 0 -}}
{{- $nanoseconds := int64 0 -}}
{{- $units := dict "ns" 1 "us" 1000 "µs" 1000 "μs" 1000 "ms" 1000000 "s" 1000000000 "m" 60000000000 "h" 3600000000000 -}}
{{- range $part := regexFindAll `([0-9]+(\.[0-9]*)?|\.[0-9]+)(ns|us|µs|μs|ms|s|m|h)` $unsigned -1 -}}
  {{- $unit := regexFind `(ns|us|µs|μs|ms|s|m|h)$` $part -}}
  {{- $unitNS := int64 (index $units $unit) -}}
  {{- $number := splitList "." (trimSuffix $unit $part) -}}
  {{- $wholeText := regexReplaceAll `^0+` (index $number 0) "" | default "0" -}}
  {{- if or (gt (len $wholeText) 19) (and (eq (len $wholeText) 19) (gt $wholeText "9223372036854775807")) -}}
    {{- fail (printf "Go duration %q overflows time.Duration" $duration) -}}
  {{- end -}}
  {{- $whole := int64 $wholeText -}}
  {{- $fractionNS := int64 0 -}}
  {{- if eq (len $number) 2 -}}
    {{/* Compute floor(fraction * unitNS) without overflowing an int64. */}}
    {{- range $digit := reverse (splitList "" (index $number 1)) -}}
      {{- $fractionNS = div (add (mul (int64 $digit) $unitNS) $fractionNS) 10 -}}
    {{- end -}}
  {{- end -}}
  {{- if ge $unitNS 1000000000 -}}
    {{- $unitSeconds := div $unitNS 1000000000 -}}
    {{- if gt $whole (div 9223372036 $unitSeconds) -}}
      {{- fail (printf "Go duration %q overflows time.Duration" $duration) -}}
    {{- end -}}
    {{- $seconds = add $seconds (mul $whole $unitSeconds) -}}
  {{- else -}}
    {{- $unitsPerSecond := div 1000000000 $unitNS -}}
    {{- $seconds = add $seconds (div $whole $unitsPerSecond) -}}
    {{- $nanoseconds = add $nanoseconds (mul (mod $whole $unitsPerSecond) $unitNS) -}}
  {{- end -}}
  {{- $nanoseconds = add $nanoseconds $fractionNS -}}
  {{- $seconds = add $seconds (div $nanoseconds 1000000000) -}}
  {{- $nanoseconds = mod $nanoseconds 1000000000 -}}
  {{- if or (gt $seconds 9223372036) (and (eq $seconds 9223372036) (gt $nanoseconds 854775807)) -}}
    {{- fail (printf "Go duration %q overflows time.Duration" $duration) -}}
  {{- end -}}
{{- end -}}
{{- if $negative -}}
  {{- if gt $seconds 2147483648 -}}
    {{- fail (printf "negative duration %q is outside the int32 seconds range" $duration) -}}
  {{- end -}}
  {{- mul $seconds -1 -}}
{{- else -}}
  {{- min $seconds 2147483647 -}}
{{- end -}}
{{- end -}}

{{/* Convert machine deletion timeouts and keep explicit zero values. */}}
{{- define "openstack-cluster.v1beta2.machineDeletion" -}}
{{- $deletion := dict -}}
{{- range $name := list "nodeDrainTimeout" "nodeVolumeDetachTimeout" "nodeDeletionTimeout" -}}
  {{- if and (hasKey $ $name) (ne (index $ $name) nil) (ne (toString (index $ $name)) "") -}}
    {{- $_ := set $deletion (printf "%sSeconds" $name) (include "openstack-cluster.v1beta2.durationSeconds" (index $ $name) | int64) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $deletion -}}
{{- end -}}

{{/* Move deployment strategy fields to their v1beta2 locations. */}}
{{- define "openstack-cluster.v1beta2.machineDeploymentStrategy" -}}
{{- $legacy := deepCopy (. | default dict) -}}
{{- $strategy := omit $legacy "remediation" -}}
{{- $result := dict -}}
{{- if not $strategy.type -}}{{- $_ := unset $strategy "type" -}}{{- end -}}
{{- with $legacy.rollingUpdate -}}
  {{- $rollingUpdate := omit . "deletePolicy" -}}
  {{- range $name := list "maxSurge" "maxUnavailable" -}}
    {{- if eq (index $rollingUpdate $name) nil -}}{{- $_ := unset $rollingUpdate $name -}}{{- end -}}
  {{- end -}}
  {{- if $rollingUpdate -}}
    {{- $_ := set $strategy "rollingUpdate" $rollingUpdate -}}
  {{- else -}}
    {{- $_ := unset $strategy "rollingUpdate" -}}
  {{- end -}}
  {{- if and (hasKey . "deletePolicy") (ne .deletePolicy nil) -}}
    {{- $_ := set $result "deletion" (dict "order" .deletePolicy) -}}
  {{- end -}}
{{- else -}}
  {{- $_ := unset $strategy "rollingUpdate" -}}
{{- end -}}
{{- if $strategy -}}
  {{- $_ := set $result "rollout" (dict "strategy" $strategy) -}}
{{- end -}}
{{- with $legacy.remediation -}}
  {{- if and (hasKey . "maxInFlight") (ne .maxInFlight nil) -}}
    {{- $_ := set $result "remediation" (dict "maxInFlight" .maxInFlight) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $result -}}
{{- end -}}

{{/*
Keep numeric and percentage health thresholds, including zero.
Remediation references still use apiVersion in v1beta2.
*/}}
{{- define "openstack-cluster.v1beta2.machineHealthCheckSpec" -}}
{{- $spec := deepCopy (. | default dict) -}}
{{- $checks := deepCopy ($spec.checks | default dict) -}}
{{- $remediation := $spec.remediation | default dict -}}
{{- $trigger := $remediation.triggerIf | default dict -}}
{{- range $legacyName, $newName := dict "unhealthyConditions" "unhealthyNodeConditions" "unhealthyMachineConditions" "unhealthyMachineConditions" -}}
  {{- if hasKey $spec $legacyName -}}
    {{- $conditions := list -}}
    {{- range $condition := index $spec $legacyName -}}
      {{- $converted := omit $condition "timeout" -}}
      {{- if and (hasKey $condition "timeout") (ne $condition.timeout nil) -}}
        {{- $_ := set $converted "timeoutSeconds" (include "openstack-cluster.v1beta2.durationSeconds" $condition.timeout | int64) -}}
      {{- end -}}
      {{- $conditions = append $conditions $converted -}}
    {{- end -}}
    {{- if $conditions -}}
      {{- $_ := set $checks $newName $conditions -}}
    {{- else -}}
      {{/* CAPI omits empty condition lists during conversion. */}}
      {{- $_ := unset $checks $newName -}}
    {{- end -}}
    {{- $_ := unset $spec $legacyName -}}
  {{- end -}}
{{- end -}}
{{- if hasKey $spec "nodeStartupTimeout" -}}
  {{- if ne $spec.nodeStartupTimeout nil -}}
    {{- $_ := set $checks "nodeStartupTimeoutSeconds" (include "openstack-cluster.v1beta2.durationSeconds" $spec.nodeStartupTimeout | int64) -}}
  {{- end -}}
  {{- $_ := unset $spec "nodeStartupTimeout" -}}
{{- end -}}
{{- range $legacyName, $newName := dict "maxUnhealthy" "unhealthyLessThanOrEqualTo" "unhealthyRange" "unhealthyInRange" -}}
  {{- if hasKey $spec $legacyName -}}
    {{- if ne (index $spec $legacyName) nil -}}
      {{- $_ := set $trigger $newName (index $spec $legacyName) -}}
    {{- end -}}
    {{- $_ := unset $spec $legacyName -}}
  {{- end -}}
{{- end -}}
{{- if hasKey $spec "remediationTemplate" -}}
  {{- with $spec.remediationTemplate -}}
    {{- $_ := set $remediation "templateRef" (pick . "apiVersion" "kind" "name") -}}
  {{- end -}}
  {{- $_ := unset $spec "remediationTemplate" -}}
{{- end -}}
{{- if $checks -}}{{- $_ := set $spec "checks" $checks -}}{{- end -}}
{{- if $trigger -}}{{- $_ := set $remediation "triggerIf" $trigger -}}{{- end -}}
{{- if $remediation -}}{{- $_ := set $spec "remediation" $remediation -}}{{- end -}}
{{- toYaml $spec -}}
{{- end -}}
