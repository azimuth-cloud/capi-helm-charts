# Migrating to v1beta2

This chart renders CAPI/CAPO resources using v1beta2 and supports existing values from chart versions `0.28.1` and `0.29.0`.
The controller versions tested in CI are listed in [dependencies.json](../dependencies.json).

Upgrade the management cluster's controllers and CRDs before applying this chart.
Use the CRDs from the same provider release, since updating controller images alone does not apply schema fixes.
Confirm that the conversion webhooks are ready to read existing v1beta1 objects as v1beta2.
Then apply this chart with the existing values file and overrides.

The chart calculates template names and hashes in the old format, then converts the output to v1beta2.
Unchanged settings keep the same template names, hashes and references.
Legacy maps such as `kubeadmConfigSpec.clusterConfiguration.apiServer.extraArgs` remain supported.
For CAPO v1beta2, `identityRef.type` is optional and defaults to `Secret`.

Keep Kubernetes versions, machine images, flavors and bootstrap settings unchanged during the API migration.
Changing these settings can replace Machines.
If an operator manages the chart, compare its generated values with the installed release's values before upgrading.
Keep settings that generate bootstrap configuration, such as Zenith, unchanged as well.

Before deploying to customers, test admission and a live upgrade in a development environment.
After upgrading the controllers and CRDs, apply the chart and verify that existing Machine UIDs and OpenStack VM IDs stay unchanged.
Compare effective resource specs through the same API version, and confirm that template names, hashes and references are unchanged.
Monitor Machine creation and deletion while the controllers reconcile, then reapply unchanged settings to check that no rollout occurs.
Matching template names alone does not prove that an upgrade will avoid Machine replacement.

Test both new installations and upgrades with an API load balancer and no floating IP.
Check that `OpenStackCluster.status.initialization.provisioned` and `Cluster.status.initialization.infrastructureProvisioned` are both `true`.
`Ready=True` alone is not enough, since a status validation error can prevent CAPO from saving the initialization state.
