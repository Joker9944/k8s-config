---
type: Playbook
title: Adding an app
description: The end-to-end sequence for introducing a new workload, including the steps Flux cannot do for you.
tags: [playbook, onboarding]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

Read [the app-template pattern](/architecture/app-template-pattern.md) first; this is the ordering, not the content.

# 1. Build the base

Create `apps/base/<name>/` (or `infrastructure/base/<name>/` for a platform service):

- `manifests/namespace.yaml` with `metadata.name: PLACEHOLDER`.
- `flux/helm-release.yaml`. Copy the closest existing neighbor rather than starting blank — the anchors, probes and security context are the convention.
- `kustomization.yaml` with `namespace: <name>`, the resources, and components. `common-kustomizeconfig` is effectively mandatory; add `bjw-s-helm-repository` when using `app-template` and `common-middlewares` when exposing an ingress.

# 2. Secrets

Pick the [shape](/workflows/secrets-sops.md) by how the value is consumed: `manifests/secret.yaml` for a Secret the workload reads, `values/secret-values.sops.yaml` plus a `secretGenerator` for values the chart needs. Encrypt with `sops -e -i`; the filename decides the rule.

# 3. Ingress

Set `router.tls`, `router.entrypoints: websecure`, `secretName: wildcard-vonarx-online-cert`, and a [middleware chain](/platform/networking-and-ingress.md) — internal whitelist for anything operational, country whitelist for anything else. Under `apps/base/` the annotation's namespace prefix is written by hand; check it matches, because nothing validates it.

# 4. Backup

If the app has a PVC worth keeping, add the `source-<vol>` / `dest-<vol>` pair and the restic Secret. If it needs Postgres, add a role to an existing CNPG cluster rather than a new one. See [backup and restore](/platform/backup-and-restore.md).

# 5. Register with Flux

Add a Kustomization to the tier's `<tier>-sync.yaml` — name and `path` only; the rest is patched in. Add `dependsOn` only for a real ordering requirement (a CRD, a Secret, a StorageClass another workload creates). Nothing is deployed until this step.

# 6. The manual steps

Flux finishes here; these do not happen on their own:

- **OIDC.** Write `kanidm-oidc.txt`, run it against kanidm by hand, and put the resulting client secret into the app's SOPS secret. See [identity](/platform/identity-kanidm.md).
- **First restore.** A recreated app starts empty unless its `dest-<vol>` is deliberately enabled once.
- **Spellcheck.** New product names need either `.config/dictionaries/project.txt` or an inline `# cSpell:ignore`. See [formatting and cspell](/workflows/formatting-and-cspell.md).

# 7. Verify

`nix fmt` before committing. `flux get kustomizations -A` and `flux get helmreleases -A` after reconciling — a level-3 Kustomization that never appears usually means it was added to the wrong `<tier>-sync.yaml`, and a HelmRelease stuck on a missing `valuesFrom` Secret usually means `common-kustomizeconfig` is not in the components list.
