---
type: Architecture
title: CUE layout
description: How the CUE tree is organized — a package per workload, a collector package per tier, and the language mechanics that force that shape.
tags: [cue, layout, gitops]
status: draft
generated: { by: claude-code/opus-5, at: 2026-09-06T18:40:00Z }
stale_after: 2027-03-06
---

The target shape for [replacing kustomize with CUE](/decisions/replace-kustomize-with-cue.md). Built for one tier in `experiments/cue/`, which carries its own README; [repo layout](/architecture/repo-layout.md) describes the kustomize tree that is still the deployed one.

# The tree

```
cue.mod/                    module github.com/joker9944/k8s-config; gen/ holds the
                            Flux definitions from cue get go
schema/                     package schema — #Release, #AppRelease, #Bundle,
                            #Hardened, #HardenedPrivileged, #Middlewares,
                            #IngressAnnotations, #ConfigMapFiles,
                            #NamespaceCert, #VolsyncRestic
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

| Component                                  | Becomes                                                                                                                                 |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `common-middlewares`                       | `#Middlewares`                                                                                                                          |
| `bjw-s-helm-repository`, `ot-helm-…`       | A `HelmRepository` emitted by `#Bundle` from the chart the releases name                                                                |
| `common-sync-patch`                        | Defaults on the level-3 `Kustomization` the tier collector emits                                                                        |
| `namespace-cert`, `namespace-cert-kanidm`  | `#NamespaceCert`, switched on with `#Bundle.namespaceCert`. Taking the namespace as a parameter retires the kustomize#5953 duplication. |
| `common-kustomizeconfig`                   | Nothing. It teaches kustomize to chase name references; CUE has no such indirection to teach.                                           |
| `blocky`/`komga` `kustomization-hack.yaml` | `#ConfigMapFiles`, whose stable name leaves nothing to chase                                                                            |

Both `PLACEHOLDER` mechanisms go with it — `namespace` is an ordinary field, and the middleware annotation is computed by `#Release`. See [kustomize components](/architecture/kustomize-components.md) for what is being replaced.

# The schema

`#Release` is a HelmRelease with the chart as a parameter (`chart`, `version`, `sourceKind`, `sourceName`), because most of the fleet outside `apps/` runs a foreign chart. `#AppRelease` embeds it and adds what the bjw-s app-template needs: the chart name, the identifier suffix, and the keyed `values.ingress.<key>` the middleware annotations are placed into. A foreign chart splices `ingressAnnotations` at whatever path its own schema uses.

The annotations come from `#IngressAnnotations`, which derives the middleware reference from the namespace it is handed — that is what stops an ingress from naming another namespace's middleware. It is a separate definition because nextcloud has two ingresses behind different middleware sets.

`#Release.crds` switches on the `install`/`upgrade` block every CRD-shipping chart carries — `crds: CreateReplace` with three remediation retries, byte-identical across the ten releases that have it. `#GitRepo` takes `branch` or `tag` plus an optional `ignore`, because two of the three git-sourced charts pin a tag and ship one directory out of a whole repository.

`#Bundle` takes `middlewares` (off where there is no ingress), `namespaceCert` (an in-cluster certificate off the private CA, for a workload that serves TLS to Traefik rather than plain HTTP), `repositories` (defaulting to the bjw-s one, replaced by a bundle on a foreign chart) and `namespaceLabels` (Pod Security admission).

Exceptions are named definitions or named fields rather than softened constraints, so `grep` finds every one: `#HardenedWritableRoot` for a container that cannot run on a read-only root, `#HardenedPrivileged` for one that must run privileged — Kubernetes rejects `privileged: true` together with `allowPrivilegeEscalation: false`, so that definition drops the field rather than the constraint — and `bareMiddleware` for a release behind a single middleware instead of a chain. The first two are policy; `bareMiddleware`, `identifierSuffix` and the three `#VolsyncRestic` escape hatches model [known drift](/architecture/config-drift.md) and go away with it.

# What kustomize was doing that CUE has to be told

- **`namespace:` overrides a source's declared namespace.** `apps/base/nextcloud/flux/helm-repository.yaml` says `namespace: flux-system` and renders as `nextcloud`. The declared value is dead; the CUE side must emit the workload namespace. One file [does declare one](/architecture/config-drift.md).
- **`secretGenerator` supplies `type: Opaque`** and a plain `secret.yaml` resource does not. A converted secret needs it written by hand; a moved one must not gain it.

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
| `cue export -e` parses `a.b-c` as subtraction                                        | A hyphenated bundle key needs a bracket selector — `tier.rendered["cert-manager"]`.                             |
| References resolve by declaration, not by embedding                                  | A derived definition must redeclare (`host: _`) every field it reads from the one it embeds.                    |
| A closed definition as a list element type rejects the fields a derived one adds     | Constrain a list by what the consumer reads (`[...{out: #HelmRelease, ...}]`), not by the definition name.      |

# Open

**`infrastructure/nyx/config/` has no CUE counterpart.** Four cluster-singleton bundles — the CA chain and Cloudflare issuer, the Longhorn storage classes, the MetalLB pool, the CNPG image catalogs — with no `base/` half and no Namespace or repository of their own. `#Bundle` emits both unconditionally, so they need a parameter before they can be expressed.

How a tier artifact is laid out internally. Each workload needs its own directory inside it, because [only level-3 Kustomizations decrypt](/architecture/flux-topology.md) and a SOPS file must sit under a path one of them reconciles. What is unresolved is how kustomize-controller treats a tier root holding both the level-3 sync manifests and those workload subdirectories with no `kustomization.yaml` present. Settle it with `flux build` before fixing the render step's output shape.
