---
type: Playbook
title: Adding an app
description: The end-to-end sequence for introducing a new workload, including the steps Flux cannot do for you.
tags: [playbook, onboarding]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-07T22:00:00Z }
---

Read [the app-template pattern](/architecture/app-template-pattern.md) first; this is the ordering, not the content.

# 1. Write the package

Create `cue/<tree>/<tier>/<name>/<name>.cue` with `package <name>`, a `#Bundle` and one `#AppRelease`. Copy the closest existing neighbour rather than starting blank — the probes, the security context and the persistence shape are the convention. The constraints do the rest: an unpinned image or a softened `readOnlyRootFilesystem` is a build error, not a review comment.

# 2. Secrets

One shape: a `Secret` manifest under `secrets/`, `data`/`stringData` encrypted. Name it for what it holds — `restic.secret.yaml` carries the volsync credential and nothing else, `<name>.secret.yaml` the rest. List it in `extraSecretFiles`; the backup brings its own in. Encrypt with `sops encrypt --in-place` **at the final repo path**, or the creation rule will not match. See [secrets and SOPS](/workflows/secrets-sops.md).

# 3. Ingress

Set `host` and, if the default `chain-country-whitelist` is wrong, `chain` — internal whitelist for anything operational. `#AppRelease` places the annotations and computes the middleware reference from the namespace, so an ingress cannot name another namespace's middleware. See [networking and ingress](/platform/networking-and-ingress.md).

# 4. Backup

If the app has a PVC worth keeping, add a `#VolsyncRestic` with its `secretFile`, put it in the release's `backups`, and give the volume a `dataSourceRef`. `dataSourceRef` is immutable, so a volume that ships without one can never gain it. If it needs Postgres, add a role to an existing CNPG cluster rather than a new one. See [backup and restore](/platform/backup-and-restore.md).

# 5. Register with the tier

Add the package to its tier collector — `cue/<tree>/<tier>/<tier>.cue`. Nothing is deployed until this step. Add `dependsOn` on the bundle only for a real ordering requirement: a CRD, a Secret or a StorageClass another workload creates.

# 6. The manual steps

Flux finishes here; these do not happen on their own:

- **OIDC.** Write `kanidm-oidc.txt`, run it against kanidm by hand, and put the resulting client secret into the app's SOPS secret. See [identity](/platform/identity-kanidm.md).
- **First restore.** A recreated app starts empty unless its `dest-<vol>` is deliberately enabled once.
- **Spellcheck.** New product names need either `.config/dictionaries/project.txt` or an inline `// cSpell:ignore`. See [formatting and cspell](/workflows/formatting-and-cspell.md).

# 7. Verify

From `cue/`: `cue vet ./...`, then render the tier with `cue cmd --inject out=./out render ./<tree>/<tier>` and read what came out. `nix fmt` before committing. After reconciling, `flux get kustomizations -A` and `flux get helmreleases -A` — a level-3 Kustomization that never appears usually means the package was never added to its tier collector.
