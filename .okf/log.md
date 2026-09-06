# Update Log

## 2026-09-06

- The four `infrastructure/nyx/config` cluster singletons ported behind a new `#ConfigBundle` — [CUE layout](/architecture/cue-layout.md)
- A SOPS filename and its encrypted body can disagree indefinitely, and re-encrypting is what breaks it — [secrets and SOPS](/workflows/secrets-sops.md)
- All 16 `infrastructure/base` workloads ported; `#NamespaceCert`, `#HardenedPrivileged`, the `crds` preset and git tags added — [CUE layout](/architecture/cue-layout.md)
- barman-cloud installs from its own chart instead of a kustomize remote resource — [backup and restore](/platform/backup-and-restore.md)
- `#NamespaceCert` retires the `namespace-cert` component pair and its kustomize#5953 workaround — [kustomize components](/architecture/kustomize-components.md)
- cspell's secret ignore widened to `*secret.yaml`, which the migrated filenames need — [formatting and cspell](/workflows/formatting-and-cspell.md)
- Manifests that diverge from the fleet's own conventions, registered — [known configuration drift](/architecture/config-drift.md)
- `#Release` split from `#AppRelease`, and `#Bundle` parameterized on middlewares, repositories and namespace labels — [CUE layout](/architecture/cue-layout.md)
- Two more CUE mechanics that decide the layout: bracket selectors and reference resolution — [CUE layout](/architecture/cue-layout.md)
- `#ConfigMapFiles` supersedes the per-app `nameReference` hack — [kustomize components](/architecture/kustomize-components.md)
- sops's YAML indent pinned to 2, which its default of 4 was breaking — [secrets and SOPS](/workflows/secrets-sops.md)
- The CUE tree reads nothing outside itself, so every whole-file secret must convert — [CUE layout](/architecture/cue-layout.md)
- Whole-file secrets are on their way out with kustomize — [secrets and SOPS](/workflows/secrets-sops.md)
- Target CUE tree: a package per workload, a collector per tier, no `components/` successor — [CUE layout](/architecture/cue-layout.md)
- `cspell-dicts` is an out-of-tree checkout rather than a submodule, and `nil` left the hook suite — [formatting and cspell](/workflows/formatting-and-cspell.md)
- Fidelity is machine-checked by `gate.sh` across every resource, not sampled — [decision](/decisions/replace-kustomize-with-cue.md)

## 2026-09-05

- conform's conventional-commit policy and the tree-shaped scope allowlist — [commit conventions](/workflows/commit-conventions.md)
- cspell hook dropped from the suite, cue-fmt and conform added — [formatting and cspell](/workflows/formatting-and-cspell.md)
- Replace kustomize with CUE, with delivery and secret handling — [decision](/decisions/replace-kustomize-with-cue.md)
- Link to the CUE decision from the layer it replaces — [kustomize components](/architecture/kustomize-components.md)
- Why the generated Secret's hash suffix matters, not just that it propagates — [app-template pattern](/architecture/app-template-pattern.md)
- `experiments/` added to the tree listing — [repo layout](/architecture/repo-layout.md)
- Initial bundle: repo layout, Flux topology, kustomize components, app-template pattern — [architecture](/architecture/index.md)
- Initial bundle: Talos cluster, networking, PKI, identity, storage, backup, observability — [platform](/platform/index.md)
- Initial bundle: adding an app, dev environment, secrets, formatting, images and CI — [workflows](/workflows/index.md)
