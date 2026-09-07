---
type: Architecture
title: CUE layout
description: How the CUE tree is organized — a package per workload, a collector package per tier, and the language mechanics that force that shape.
tags: [cue, layout, gitops]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-07T21:00:00Z }
stale_after: 2027-03-06
---

The target shape for [replacing kustomize with CUE](/decisions/replace-kustomize-with-cue.md). Built for one tier in `experiments/cue/`, which carries its own README; [repo layout](/architecture/repo-layout.md) describes the kustomize tree that is still the deployed one.

# The tree

```
cue.mod/                    module github.com/joker9944/k8s-config; gen/ holds the
                            Flux definitions from cue get go
render_tool.cue             package tier — the `cue cmd render` workflow
schema/                     package schema — #Release, #AppRelease, #Bundle,
                            #ConfigBundle, #Hardened, #HardenedPrivileged,
                            #Middlewares, #IngressAnnotations, #ConfigMapFiles,
                            #NamespaceCert, #VolsyncRestic
infrastructure/
  controllers/
    controllers.cue         package controllers — the tier collector
    traefik/
      traefik.cue           package traefik
      files/                plaintext read with @embed
      secrets/*.secret.yaml inert to CUE; copied verbatim by the render step
apps/
  media/
    media.cue               package media
    jellyfin/jellyfin.cue
clusters/nyx/flux/          package flux — the level-2 Kustomizations and their
                            OCIRepositories, plus `cue cmd bootstrap`
```

**Every tier collector is `package tier`.** A workflow command only applies to
instances whose package clause matches the tool file's, so eight differently
named packages would need eight copies of the render. The directory is the
identity instead, declared as `tree` and `name` on `#Tier`; nothing imports a
collector, so the name is free.

A workload is a package. A tier is a package that imports its workloads and is also the OCI artifact boundary, so `cue export ./apps/media -e rendered` is both the unit of rendering and the unit of blast radius.

`#ConfigBundle` is the other kind of bundle: a pile of cluster resources with no namespace of its own, no chart and no releases — the CA chain, the storage classes, the MetalLB pool, the CNPG image catalogs. It sits in the tier that reconciles it, so `certs-config` is a package under `infrastructure/controllers/` alongside `cert-manager`.

**There is no `base/` and no `nyx/`.** The tier collector is simultaneously the tier definition and the cluster overlay. `nyx` is the only cluster and nothing under `base/` was ever parameterized per cluster, so the split is spent rather than preserved; a second cluster would reintroduce it as `clusters/<name>/` collectors.

**`components/` has no successor tree.** Its contents become definitions in `schema/`:

| Component                                  | Becomes                                                                                                                                 |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `common-middlewares`                       | `#Middlewares`                                                                                                                          |
| `bjw-s-helm-repository`, `ot-helm-…`       | A `HelmRepository` emitted by `#Bundle` from the chart the releases name                                                                |
| `common-sync-patch`                        | `#Tier.sync`, which generates the level-3 `Kustomization`s rather than patching them                                                    |
| `namespace-cert`, `namespace-cert-kanidm`  | `#NamespaceCert`, switched on with `#Bundle.namespaceCert`. Taking the namespace as a parameter retires the kustomize#5953 duplication. |
| `common-kustomizeconfig`                   | Nothing. It teaches kustomize to chase name references; CUE has no such indirection to teach.                                           |
| `blocky`/`komga` `kustomization-hack.yaml` | `#ConfigMapFiles`, whose stable name leaves nothing to chase                                                                            |

Both `PLACEHOLDER` mechanisms go with it — `namespace` is an ordinary field, and the middleware annotation is computed by `#Release`. See [kustomize components](/architecture/kustomize-components.md) for what is being replaced.

# The schema

`#Release` is a HelmRelease with the chart as a parameter (`chart`, `version`, `sourceKind`, `sourceName`), because most of the fleet outside `apps/` runs a foreign chart. `#AppRelease` embeds it and adds what the bjw-s app-template needs: the chart name, the identifier suffix, and the keyed `values.ingress.<key>` the middleware annotations are placed into. A foreign chart splices `ingressAnnotations` at whatever path its own schema uses.

The annotations come from `#IngressAnnotations`, which derives the middleware reference from the namespace it is handed — that is what stops an ingress from naming another namespace's middleware. It is a separate definition because nextcloud has two ingresses behind different middleware sets.

`#Release.crds` switches on the `install`/`upgrade` block every CRD-shipping chart carries — `crds: CreateReplace` with three remediation retries, byte-identical across the ten releases that have it. `#GitRepo` takes `branch` or `tag` plus an optional `ignore`, because two of the three git-sourced charts pin a tag and ship one directory out of a whole repository.

`#Bundle` takes `middlewares` (off where there is no ingress), `namespaceCert` (an in-cluster certificate off the private CA, for a workload that serves TLS to Traefik rather than plain HTTP), `repositories` (defaulting to the bjw-s one, replaced by a bundle on a foreign chart) and `namespaceLabels` (Pod Security admission).

`#VolsyncRestic` takes the SOPS manifest holding its credential Secret as an input — `<workload>/secrets/restic.secret.yaml`, which carries restic credentials and nothing else — so a [backup](/platform/backup-and-restore.md) and the credential it cannot run without are declared together. It exposes the `<app>-restic-<vol>` name that manifest and the `ReplicationSource` have to agree on. `#Bundle.secretFiles` is derived from it — the backups' files plus `extraSecretFiles`, deduplicated through a struct, because a workload usually keeps its restic credential in the same file as its other Secrets. CUE holds the path and never the ciphertext, so the other half is the gate's: every `ReplicationSource` it renders must name a Secret the bundle emits.

**No release takes its values from a Secret.** `spec.valuesFrom` merges the payload into the release, so the material stops being a Secret the moment the chart renders — loki's S3 credentials landed in a plain `ConfigMap` that way. Every workload uses its chart's own mechanism instead: `secretKeyRef` and `envFrom` where the chart offers them, pgadmin's `existingSecret`, and for loki `-config.expand-env=true` with the credentials injected per component. `#Release` carries no field for the old shape, so a bundle cannot reintroduce it.

Exceptions are named definitions rather than softened constraints, so `grep` finds every one: `#HardenedWritableRoot` for a container that cannot run on a read-only root, and `#HardenedPrivileged` for one that must run privileged — Kubernetes rejects `privileged: true` together with `allowPrivilegeEscalation: false`, so that definition drops the field rather than the constraint. Both are policy. There are no others: a workload that would need one is a workload that has to change.

# What kustomize was doing that CUE has to be told

- **`namespace:` overrides a source's declared namespace.** `apps/base/nextcloud/flux/helm-repository.yaml` says `namespace: flux-system` and renders as `nextcloud`; metallb's `IPAddressPool` and `L2Advertisement` say `metallb` against a `metallb-system` overlay. The declared value is dead either way, and the CUE side must emit the workload namespace. `infrastructure/base/alloy/flux/helm-repository.yaml` declares `${app_namespace:=alloy}` there, a Flux post-build variable nothing substitutes — kustomize overwrites it before Flux ever sees it.
- **`secretGenerator` supplies `type: Opaque`** and a plain `secret.yaml` resource does not. A converted secret needs it written by hand; a moved one must not gain it.

# The render is CUE

`cue cmd --inject out=<dir> render ./<tree>/<tier>` writes one tier. Every task —
the directories, the manifests, the copied secrets, the sync file — is produced
by a comprehension over `tier.bundles`, so adding a workload adds its files with
nothing in the workflow to edit.

```
<out>/<tree>/<tier>/
  sync/<tier>-sync.yaml     the level-3 Kustomizations
  <bundle>/manifests.yaml   everything the bundle declares
  <bundle>/*.secret.yaml    copied byte for byte
```

The sync manifests sit in `sync/` rather than at the artifact root because
[a generated kustomization walks subdirectories](/architecture/flux-topology.md).
`#Tier.sync` generates them, which is what retires `common-sync-patch`: interval,
timeout, prune, `sourceRef` and `decryption` were that component's entire content.

Secrets are copied with `tool/file.Read` into `tool/file.Create`. That is not the
thing the rules forbid — what is forbidden is `@embed` on a SOPS file, which puts
ciphertext into a `.cue` file and reproduces the shape `forbid_secrets` rejects.
The copy happens at command time, lands in no source file, and decrypts nothing.

# The tree reads nothing outside itself

A workload's plaintext files and SOPS secrets live in its own package, because a replacement that sources from the tree it replaces breaks the moment that tree is deleted. Two consequences that are easy to miss:

- **`secretGenerator` has no successor.** A whole-file `*.sops.yaml` left as-is is a resource nothing renders, so every one becomes a `secret.yaml` manifest. The conversion has to supply two fields kustomize used to inject — `metadata.namespace` and `type: Opaque` — and neither failure is loud.
- **Comparing a migrated secret means decrypting it.** Re-encrypting identical plaintext yields different ciphertext, so a byte comparison of two encrypted files proves only that neither was touched.

See [secrets and SOPS](/workflows/secrets-sops.md) for the naming rule a converted file has to match.

# What the mechanics force

Verified against cue v0.16.1. Each of these eliminated a layout that otherwise looked reasonable.

| Mechanic                                                                             | Consequence                                                                                                                                                               |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cue export ./...` evaluates instances separately rather than merging them           | A cross-tier expression needs a package importing each tier by name. There is no glob import.                                                                             |
| `@tag` values do not reach imported packages — injection hits only the root instance | Tags cannot live in `schema/`. Prefer `@embed` and keep the layout free of them.                                                                                          |
| `@embed` cannot refer to a parent directory                                          | A workload's plaintext files must sit at or below its own package. This is what makes the workload the package.                                                           |
| `@embed(glob=…)` yields a map keyed by relative path                                 | A file set needs no enumeration.                                                                                                                                          |
| A package name must be an identifier, so a hyphenated directory cannot supply one    | Most imports carry an explicit qualifier: `import cm ".../cert-manager:certmanager"`.                                                                                     |
| `cue vet ./...` does span every package                                              | Validation stays one command.                                                                                                                                             |
| `cue export -e` parses `a.b-c` as subtraction                                        | A hyphenated bundle key needs a bracket selector — `tier.rendered["cert-manager"]`.                                                                                       |
| References resolve by declaration, not by embedding                                  | A derived definition must redeclare (`host: _`) every field it reads from the one it embeds.                                                                              |
| A closed definition used as an element type rejects anything but itself              | Constrain a collection by what the consumer reads (`[...{out: #HelmRelease, ...}]`), not by the definition name. This bit `#Bundle.releases` and `#Tier.bundles` in turn. |
| A `_tool.cue` only applies to instances sharing its package clause                   | One workflow across many directories means one package name across them. Hence `package tier` for all eight collectors.                                                   |

# Open

How the artifact reaches the registry. The rendered tree is complete and `flux build` walks it, but nothing pushes it: there is no CI job, and `OCIRepository.spec.verify` is deliberately absent because nothing signs the artifacts yet. Both belong with [the signing machinery the images already use](/workflows/images-and-ci.md).

The rendered bytes also depend on the `cue` version — 0.16.1 and 0.17.1 order YAML keys differently, so a toolchain bump changes every artifact digest without changing any resource. Worth pinning deliberately before digests start mattering.
