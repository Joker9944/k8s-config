---
type: Architecture
title: CUE layout
description: How the CUE tree is organized — a package per workload, a collector package per tier, and the language mechanics that force that shape.
tags: [cue, layout, gitops]
status: draft
generated: { by: claude-code/opus-5, at: 2026-09-06T07:05:00Z }
stale_after: 2027-03-06
---

The target shape for [replacing kustomize with CUE](/decisions/replace-kustomize-with-cue.md). Built for one tier in `experiments/cue/`, which carries its own README; [repo layout](/architecture/repo-layout.md) describes the kustomize tree that is still the deployed one.

# The tree

```
cue.mod/                    module github.com/joker9944/k8s-config; gen/ holds the
                            Flux definitions from cue get go
schema/                     package schema — #Release, #Bundle, #Hardened,
                            #Middlewares, #NamespaceCert, #VolsyncRestic
infrastructure/
  controllers/
    controllers.cue         package controllers — the tier collector
    traefik/
      traefik.cue           package traefik
      files/                plaintext read with @embed
      secrets/*.sops.yaml   inert to CUE; copied verbatim by the render step
apps/
  media/
    media.cue               package media
    jellyfin/jellyfin.cue
clusters/nyx/               unchanged: Talos, bootstrap, and the level-2 tier
                            Kustomizations, now backed by OCIRepository
```

A workload is a package. A tier is a package that imports its workloads and is also the OCI artifact boundary, so `cue export ./apps/media -e rendered` is both the unit of rendering and the unit of blast radius.

**There is no `base/` and no `nyx/`.** The tier collector is simultaneously the tier definition and the cluster overlay. `nyx` is the only cluster and nothing under `base/` was ever parameterized per cluster, so the split is spent rather than preserved; a second cluster would reintroduce it as `clusters/<name>/` collectors.

**`components/` has no successor tree.** Its contents become definitions in `schema/`:

| Component                                 | Becomes                                                                                                |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `common-middlewares`                      | `#Middlewares`                                                                                         |
| `bjw-s-helm-repository`, `ot-helm-…`      | A `HelmRepository` emitted by `#Bundle` from the chart the releases name                               |
| `common-sync-patch`                       | Defaults on the level-3 `Kustomization` the tier collector emits                                       |
| `namespace-cert`, `namespace-cert-kanidm` | One `#NamespaceCert` taking the namespace as a parameter, which retires the kustomize#5953 duplication |
| `common-kustomizeconfig`                  | Nothing. It teaches kustomize to chase name references; CUE has no such indirection to teach.          |

Both `PLACEHOLDER` mechanisms go with it — `namespace` is an ordinary field, and the middleware annotation is computed by `#Release`. See [kustomize components](/architecture/kustomize-components.md) for what is being replaced.

# The tree reads nothing outside itself

A workload's plaintext files and SOPS secrets live in its own package, because a replacement that sources from the tree it replaces breaks the moment that tree is deleted. Two consequences that are easy to miss:

- **`secretGenerator` has no successor.** A whole-file `*.sops.yaml` left as-is is a resource nothing renders, so every one becomes a `secret.yaml` manifest. The conversion has to supply two fields kustomize used to inject — `metadata.namespace` and `type: Opaque` — and neither failure is loud.
- **Comparing a migrated secret means decrypting it.** Re-encrypting identical plaintext yields different ciphertext, so a byte comparison of two encrypted files proves only that neither was touched.

See [secrets and SOPS](/workflows/secrets-sops.md) for the naming rule a converted file has to match.

# What the mechanics force

Verified against cue v0.16.1. Each of these eliminated a layout that otherwise looked reasonable.

| Mechanic                                                                             | Consequence                                                                                                     |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| `cue export ./...` evaluates instances separately rather than merging them           | A cross-tier expression needs a package importing each tier by name. There is no glob import.                   |
| `@tag` values do not reach imported packages — injection hits only the root instance | Tags cannot live in `schema/`. Prefer `@embed` and keep the layout free of them.                                |
| `@embed` cannot refer to a parent directory                                          | A workload's plaintext files must sit at or below its own package. This is what makes the workload the package. |
| `@embed(glob=…)` yields a map keyed by relative path                                 | A file set needs no enumeration.                                                                                |
| A package name must be an identifier, so a hyphenated directory cannot supply one    | Most imports carry an explicit qualifier: `import cm ".../cert-manager:certmanager"`.                           |
| `cue vet ./...` does span every package                                              | Validation stays one command.                                                                                   |

# Open

How a tier artifact is laid out internally. Each workload needs its own directory inside it, because [only level-3 Kustomizations decrypt](/architecture/flux-topology.md) and a SOPS file must sit under a path one of them reconciles. What is unresolved is how kustomize-controller treats a tier root holding both the level-3 sync manifests and those workload subdirectories with no `kustomization.yaml` present. Settle it with `flux build` before fixing the render step's output shape.
