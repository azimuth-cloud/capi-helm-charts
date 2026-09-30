# Migrating to v1beta2

This chart renders CAPI/CAPO resources using v1beta2 and supports existing values from chart versions `0.28.1` and `0.29.0`.
The migration targets CAPI `v1.14.2` and CAPO `v0.15.0`.

Upgrade the management cluster's controllers and CRDs before applying this chart.
Confirm that the conversion webhooks are ready to read existing v1beta1 objects as v1beta2.
Then apply this chart with the existing values file and overrides.

The chart calculates template names and hashes in the old format, then converts the output to v1beta2.
Unchanged settings keep the same template names, hashes and references.
Legacy maps such as `kubeadmConfigSpec.clusterConfiguration.apiServer.extraArgs` remain supported.
For CAPO v0.15.0 v1beta2, `identityRef.type` is optional and defaults to `Secret`.

Keep Kubernetes versions, machine images, flavors and bootstrap settings unchanged during the API migration.
Changing these settings can replace Machines.

Before deploying to customers, test admission and a live upgrade in a development environment.
After upgrading the controllers and CRDs, apply the chart and verify that existing Machine UIDs and OpenStack VM IDs stay unchanged.
Matching template names alone does not prove that an upgrade will avoid Machine replacement.
