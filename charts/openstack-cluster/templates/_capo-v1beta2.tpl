{{/*
Convert specs for output using CAPO v0.15.0's conversion rules.
Keep the original specs for hashing so template names stay the same.
Check for nil rather than empty values to preserve explicit false and zero.
*/}}

{{- define "openstack-cluster.capo.v1beta2.machineSpec" -}}
{{- $spec := deepCopy . -}}
{{- if ne $spec.flavorID nil -}}
{{- $_ := set $spec "flavor" (dict "id" $spec.flavorID) -}}
{{- else if and (ne $spec.flavor nil) (not (kindIs "map" $spec.flavor)) -}}
{{- $_ := set $spec "flavor" (dict "filter" (dict "name" $spec.flavor)) -}}
{{- end -}}
{{- $_ := unset $spec "flavorID" -}}
{{- range $port := $spec.ports -}}
{{- if ne $port.disablePortSecurity nil -}}
{{- $_ := set $port "enablePortSecurity" (not $port.disablePortSecurity) -}}
{{- end -}}
{{- $_ := unset $port "disablePortSecurity" -}}
{{- end -}}
{{- toYaml $spec -}}
{{- end -}}

{{- define "openstack-cluster.capo.v1beta2.machineTemplateSpec" -}}
{{- $spec := deepCopy . -}}
{{- $_ := set $spec.template "spec" (include "openstack-cluster.capo.v1beta2.machineSpec" $spec.template.spec | fromYaml) -}}
{{- toYaml $spec -}}
{{- end -}}

{{- define "openstack-cluster.capo.v1beta2.clusterSpec" -}}
{{- $spec := deepCopy . -}}
{{- if ne $spec.disableExternalNetwork nil -}}
{{- $_ := set $spec "enableExternalNetwork" (not $spec.disableExternalNetwork) -}}
{{- end -}}
{{- $_ := unset $spec "disableExternalNetwork" -}}

{{- $apiServer := $spec.apiServer | default dict -}}
{{- range $old, $new := dict "apiServerFloatingIP" "floatingIP" "apiServerFixedIP" "fixedIP" "apiServerPort" "port" "apiServerLoadBalancer" "managedLoadBalancer" -}}
{{- if ne (index $spec $old) nil -}}
{{- $_ := set $apiServer $new (index $spec $old) -}}
{{- end -}}
{{- $_ := unset $spec $old -}}
{{- end -}}
{{- if ne $spec.disableAPIServerFloatingIP nil -}}
{{- $_ := set $apiServer "enableFloatingIP" (not $spec.disableAPIServerFloatingIP) -}}
{{- end -}}
{{- $_ := unset $spec "disableAPIServerFloatingIP" -}}
{{- if $apiServer -}}
{{- $_ := set $spec "apiServer" $apiServer -}}
{{- end -}}

{{- $network := $spec.managedNetwork | default dict -}}
{{- if ne $spec.networkMTU nil -}}
{{- $_ := set $network "mtu" $spec.networkMTU -}}
{{- end -}}
{{- $_ := unset $spec "networkMTU" -}}
{{- if ne $spec.disablePortSecurity nil -}}
{{- $_ := set $network "enablePortSecurity" (not $spec.disablePortSecurity) -}}
{{- end -}}
{{- $_ := unset $spec "disablePortSecurity" -}}
{{- if $network -}}
{{- $_ := set $spec "managedNetwork" $network -}}
{{- end -}}

{{- if $spec.externalRouterIPs -}}
{{- $_ := set $spec "managedRouter" (dict "externalIPs" $spec.externalRouterIPs) -}}
{{- end -}}
{{- $_ := unset $spec "externalRouterIPs" -}}
{{- with $spec.managedSecurityGroups -}}
{{- if .allNodesSecurityGroupRules -}}
{{- $_ := set . "clusterNodesSecurityGroupRules" .allNodesSecurityGroupRules -}}
{{- end -}}
{{- $_ := unset . "allNodesSecurityGroupRules" -}}
{{- end -}}
{{- with $spec.bastion -}}
{{- with .spec -}}
{{- $_ := set $spec.bastion "spec" (include "openstack-cluster.capo.v1beta2.machineSpec" . | fromYaml) -}}
{{- end -}}
{{- end -}}
{{- toYaml $spec -}}
{{- end -}}
