---
type: Architecture
title: Flux topology
description: The three-level Kustomization graph that reconciles nyx, and the ordering constraints encoded in it.
tags: [gitops, flux, reconciliation]
resource: clusters/nyx/flux
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# Three levels

**1. Bootstrap.** `clusters/nyx/flux/flux-system/gotk-sync.yaml` is flux-generated (`DO NOT EDIT`). It defines the `flux-system` `GitRepository` — `ssh://git@github.com/joker9944/k8s-config`, branch `main`, 1m interval — and a Kustomization reconciling `./clusters/nyx/flux`.

**2. Tiers.** `clusters/nyx/flux/infrastructure-sync.yaml` and `app-sync.yaml` define eight Kustomizations in `flux-system`, each **fully specified inline** (30m interval, `prune: true`, explicit `sourceRef`):

| Tier            | Path                               | `dependsOn`   |
| --------------- | ---------------------------------- | ------------- |
| `controllers`   | `infrastructure/nyx/controllers`   | —             |
| `plugins`       | `infrastructure/nyx/plugins`       | —             |
| `observability` | `infrastructure/nyx/observability` | `controllers` |
| `security`      | `infrastructure/nyx/security`      | `controllers` |
| `storage`       | `infrastructure/nyx/storage`       | `controllers` |
| `cloud`         | `apps/nyx/cloud`                   | `controllers` |
| `media`         | `apps/nyx/media`                   | `controllers` |
| `utility`       | `apps/nyx/utility`                 | `controllers` |

**3. Workloads.** Each tier directory's `<tier>-sync.yaml` holds one Kustomization per workload, reduced to `metadata.name`, `spec.path` and — where needed — `dependsOn` or `healthChecks`. Everything else is patched in by the [`common-sync-patch` component](/architecture/kustomize-components.md), which the tier's `kustomization.yaml` pulls in alongside `namespace: flux-system`.

# Ordering

Level-3 `dependsOn` edges exist where a workload needs a CRD, a Secret or a StorageClass another one creates:

- `<x>-config` → `<x>`: `certs-config`→`cert-manager`, `metallb-config`→`metallb`, `longhorn-config`→`longhorn`, `cnpg-config`→`cnpg`.
- `traefik` → `certs-config`, `metallb-config`, `redis-operator`.
- `loki` → `garage`; `alloy` → `loki`; `gotify` → `kube-prometheus-stack`.

`certs-config` also declares `healthChecks` on the `wildcard-vonarx-online` and `nyx-intermediate-ca` Certificates, so the controllers tier blocks until [PKI](/platform/certificates-and-pki.md) is actually issued rather than merely applied.

# Traps

- **Only level-3 Kustomizations can decrypt.** `decryption.provider: sops` comes from `common-sync-patch`, which is applied inside the overlay directories. A SOPS file must therefore live under a path reconciled by a level-3 Kustomization (`*/base/*` or `infrastructure/nyx/config/*`), never in a tier directory itself.
- **`clusters/nyx/bootstrap.sh` is stale.** It bootstraps `--branch=cluster-migration` while `gotk-sync.yaml` tracks `main`. The script is a one-time record of how the cluster was stood up, not a re-runnable procedure.
