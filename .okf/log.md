# Update Log

## 2026-09-08

- CI publishes and cosign-signs one OCI artifact per tier, gated on a hash of the rendered tree — [images, CI and dependency updates](/workflows/images-and-ci.md)
- A tier's derivation sees only `schema/` and its own directory, and `$out` is the artifact root — [CUE layout](/architecture/cue-layout.md)
- `devShells.ci` gains `fluxcd` and has a second consumer — [development environment](/workflows/dev-environment.md)
- Level 2 verifies each artifact against the publishing workflow's keyless cosign identity on `main` — [Flux topology](/architecture/flux-topology.md)

## 2026-09-07

- kustomize deleted; the CUE module is the tree, under `cue/` — [repo layout](/architecture/repo-layout.md)
- `verify.sh` checks that a backup's credential Secret is in the file the backup names — [CUE layout](/architecture/cue-layout.md)
- A stable ConfigMap or Secret name means a content edit rolls nothing — [CUE layout](/architecture/cue-layout.md)
- Level 2 reads a per-tier OCI artifact, which nothing publishes yet — [Flux topology](/architecture/flux-topology.md)
- The `components/` concept retired with the tree it described — [CUE layout](/architecture/cue-layout.md)
- One secret shape, and the package shape that replaces the overlay directory — [app-template pattern](/architecture/app-template-pattern.md)
- Renovate reads `.cue` through regex managers; the stock flux ones are off — [images, CI and dependency updates](/workflows/images-and-ci.md)
- The onboarding sequence is CUE, not kustomize — [adding an app](/workflows/adding-an-app.md)
- Only talhelper still uses the whole-file SOPS rule — [secrets and SOPS](/workflows/secrets-sops.md)
- `cue/` splits into three commit scopes — [commit conventions](/workflows/commit-conventions.md)
- No CUE release takes its values from a Secret; `spec.valuesFrom` leaks the payload into the render — [CUE layout](/architecture/cue-layout.md)
- The volsync credential Secret is an input of `#VolsyncRestic`, and `#Bundle.secretFiles` derives from it — [CUE layout](/architecture/cue-layout.md)
- Nothing in the kustomize tree binds a backup to the Secret it needs — [backup and restore](/platform/backup-and-restore.md)
- Every registered configuration drift corrected in CUE; the register is retired — [CUE layout](/architecture/cue-layout.md)
- `metallb.io` is the annotation domain; `metallb.universe.tf` is deprecated upstream — [networking and ingress](/platform/networking-and-ingress.md)
- `dataSourceRef` is immutable, so every backed-up volume declares one up front — [backup and restore](/platform/backup-and-restore.md)
- A sops MAC spans every document in a multi-document file — [secrets and SOPS](/workflows/secrets-sops.md)
- A green gate means every disagreement is allowlisted, not that the trees agree — [decision](/decisions/replace-kustomize-with-cue.md)
- `cue` single-sourced from the dev shell, so nothing evaluates the tree with a second version — [development environment](/workflows/dev-environment.md)

## 2026-09-06

- The whole fleet renders to a deployable tree with `cue cmd`, no shell step — [CUE layout](/architecture/cue-layout.md)
- Level-3 Kustomizations modelled as `#Tier.sync`, which retires `common-sync-patch` — [CUE layout](/architecture/cue-layout.md)
- A generated `kustomization.yaml` walks subdirectories, so sync manifests need their own — [Flux topology](/architecture/flux-topology.md)
- The four `infrastructure/nyx/config` cluster singletons ported behind a new `#ConfigBundle` — [CUE layout](/architecture/cue-layout.md)
- A SOPS filename and its encrypted body can disagree indefinitely, and re-encrypting is what breaks it — [secrets and SOPS](/workflows/secrets-sops.md)
- All 16 `infrastructure/base` workloads ported; `#NamespaceCert`, `#HardenedPrivileged`, the `crds` preset and git tags added — [CUE layout](/architecture/cue-layout.md)
- barman-cloud installs from its own chart instead of a kustomize remote resource — [backup and restore](/platform/backup-and-restore.md)
- `#NamespaceCert` retires the `namespace-cert` component pair and its kustomize#5953 workaround — [CUE layout](/architecture/cue-layout.md)
- cspell's secret ignore widened to `*secret.yaml`, which the migrated filenames need — [formatting and cspell](/workflows/formatting-and-cspell.md)
- `#Release` split from `#AppRelease`, and `#Bundle` parameterized on middlewares, repositories and namespace labels — [CUE layout](/architecture/cue-layout.md)
- Two more CUE mechanics that decide the layout: bracket selectors and reference resolution — [CUE layout](/architecture/cue-layout.md)
- `#ConfigMapFiles` supersedes the per-app `nameReference` hack — [CUE layout](/architecture/cue-layout.md)
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
- Why the generated Secret's hash suffix matters, not just that it propagates — [app-template pattern](/architecture/app-template-pattern.md)
- `experiments/` added to the tree listing — [repo layout](/architecture/repo-layout.md)
- Initial bundle: repo layout, Flux topology, kustomize components, app-template pattern — [architecture](/architecture/index.md)
- Initial bundle: Talos cluster, networking, PKI, identity, storage, backup, observability — [platform](/platform/index.md)
- Initial bundle: adding an app, dev environment, secrets, formatting, images and CI — [workflows](/workflows/index.md)
