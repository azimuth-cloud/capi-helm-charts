# v1beta2 migration tests

The chart accepts existing values and renders CAPI/CAPO v1beta2 resources.
Unchanged settings must keep the same template names, hashes and references.
Infrastructure or bootstrap changes must still update the affected templates.

## Upgrade order and compatibility

Upgrade the management cluster's controllers and CRDs to CAPI `v1.14.2` and CAPO `v0.15.0` before applying this chart.
Confirm that the conversion webhooks are ready to read existing v1beta1 objects as v1beta2.

Keep the existing values file and overrides.
Legacy maps such as `kubeadmConfigSpec.clusterConfiguration.apiServer.extraArgs` remain supported.
The chart merges values and calculates template names and hashes in the old format, then converts the output to v1beta2.

For CAPO v0.15.0 v1beta2, `identityRef.type` is optional and defaults to `Secret`.
The chart can omit it and pass validation without changing the schema.

Keep Kubernetes versions, machine images, flavors and bootstrap settings unchanged during the API migration.
Changing these settings can replace Machines.

## Run the tests

Use Helm 3.15.3, Python 3.9 or newer, and the pinned PyYAML dependency.
The script compares rendered charts locally without contacting a cluster.
The old Git references must be available locally.

```sh
python3 -m venv .artifacts/capo-validation/migration-venv
.artifacts/capo-validation/migration-venv/bin/pip install -r scripts/requirements-migration.txt
.artifacts/capo-validation/migration-venv/bin/python scripts/check-v1beta2-migration.py \
  --helm /path/to/helm
```

The Helm Lint workflow runs these tests before checking out the previous release's values.
Separate CI steps run strict kubeconform validation with current and previous-release values using the pinned catalog in `.github/workflows/lint.yaml`.
They include CAPO resources and skip only `HelmRelease` and `Manifests`.
Schema validation does not cover every scenario in this script.

`--output-dir` selects a new directory for results.
`--baseline-ref` selects the pre-migration main commit (default `390e8a99`).
Repeat `--old-tag` to replace the default historical tags `0.28.1` and `0.29.0`.

## What is compared

The script copies each old chart and its local addon dependency from Git.
It renders the old and working charts with the same release name, namespace, values and overrides.

For each of the three baselines it checks nine scenarios:

- Base, full and OVN fixtures with the exact historical default values file.
- Current defaults with legacy maps at every kubeadm `extraArgs` path, including OIDC and explicit argument overrides.
- Explicit `false`, zero durations and zero unhealthy thresholds.
- Node group overrides, checking that a second group is unaffected.
- Fractional durations, multi-unit durations and disabled certificate rollout.
- Empty bootstrap file content, optional `false` fields, a null discovery file, empty taint lists and the legacy discovery timeout on Flatcar/Ignition.
- Empty component environment lists, default local API endpoint fields and an empty control plane join configuration.

Across these 27 render pairs it compares resource names, template checksums, references, bootstrap file contents and commands, argument values and order, Kubernetes versions, replicas, deletion timeouts, health-check conditions, rollout policy and selected CAPO settings.
It also requires all seven migrated resource kinds to use v1beta2.

The comparison follows API defaults for optional `false` fields and KCP's handling of empty environment lists.
It preserves argument order and duplicates, full file contents, empty taint lists and `joinConfiguration.controlPlane: {}`.

Three additional scenarios change the control-plane flavor, one worker flavor, or one worker's bootstrap arguments.
Each must change only the affected template name and checksum.
Other templates must stay unchanged, and each reference must point to a rendered template.

Each run saves rendered YAML, Helm stderr and a `report.json` under `.artifacts/capo-validation/`.
The report records baseline commit SHAs, Helm version, differences and comparison results.
Generated artifacts are not committed.
CI uploads the output and report as the `v1beta2-migration-comparison` artifact, including when a comparison fails.

## What this does not prove

These tests check selected fields.
They do not run the upstream conversion webhooks or prove that the API server will accept an update.
Keeping a template's name is valid only when its effective configuration stays the same, especially for immutable OpenStackMachineTemplate specs and KCP bootstrap configuration.

Before deploying to customers, test admission and a live upgrade.
Upgrade the controllers and CRDs first, then the chart, and verify that existing Machine UIDs and OpenStack VM IDs stay unchanged.
