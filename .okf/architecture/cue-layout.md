---
type: Architecture
title: CUE layout
description: How the CUE tree is organized — a package per workload, a collector package per tier, and the language mechanics that force that shape.
tags: [cue, layout, gitops]
status: stable
generated: { by: claude-code/fable-5, at: 2026-09-11T15:00:00Z }
stale_after: 2027-03-06
---

CUE is the composition layer, [replacing kustomize](/decisions/replace-kustomize-with-cue.md). The whole module lives under `cue/`; [repo layout](/architecture/repo-layout.md) places it among the other trees.

# The tree

```
cue/
  cue.mod/                  module github.com/joker9944/k8s-config; gen/ holds the
                            Flux definitions from cue get go
  render_tool.cue           package tier — the `cue cmd render` workflow
  render.nix                one derivation per tier, plus the bootstrap layer
  generate.sh               regenerates cue.mod/gen from the running Flux versions
  probe/                    package probe — mutation tests on the schema
  schema/                   package schema — #Release, #AppRelease, #Bundle,
                            #ConfigBundle, #Hardened, #HardenedPrivileged,
                            #Middlewares, #IngressAnnotations, #ConfigMapFiles,
                            #NamespaceCert, #VolsyncRestic, #AlloyPipeline,
                            #Reserved, #MediaData, #PodCIDR, #ServiceCIDR
  infrastructure/
    controllers/
      controllers.cue       package controllers — the tier collector
      traefik/
        traefik.cue         package traefik
        files/              plaintext read with @embed
        secrets/*.secret.yaml  inert to CUE; copied verbatim by the render step
  apps/
    media/
      media.cue             package media
      jellyfin/jellyfin.cue
  clusters/nyx/flux/        package flux — the level-2 Kustomizations and their
                            OCIRepositories, plus `cue cmd bootstrap`
```

# Running it

```sh
cue cmd --inject out=./out render ./apps/media     # one tier
cue cmd --inject out=.. bootstrap ./clusters/nyx/flux
nix build .#cue-render-media                       # the same, hermetically
cue vet -c ./...                                   # includes probe/; also checks.cueVet
```

`cue` comes from the dev shell so `generate.sh`, `render.nix`, `checks.cueVet` and
the artifacts all evaluate with one version. See
[the development environment](/workflows/dev-environment.md).

**Every tier collector is `package tier`.** A workflow command only applies to
instances whose package clause matches the tool file's, so eight differently
named packages would need eight copies of the render. The directory is the
identity instead, declared as `tree` and `name` on `#Tier`; nothing imports a
collector, so the name is free.

A workload is a package. A tier is a package that imports its workloads and is also the OCI artifact boundary, so `cue export ./apps/media -e rendered` is both the unit of rendering and the unit of blast radius.

`#ConfigBundle` is the other kind of bundle: a pile of cluster resources with no namespace of its own, no chart and no releases — the CA chain, the storage classes, the MetalLB pool, the CNPG image catalogs. It sits in the tier that reconciles it, so `certs-config` is a package under `infrastructure/controllers/` alongside `cert-manager`.

**The kustomize `components/` tree has no successor.** Its contents are definitions in `schema/`:

| Component                                  | Becomes                                                                                                                                 |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `common-middlewares`                       | `#Middlewares`                                                                                                                          |
| `bjw-s-helm-repository`, `ot-helm-…`       | A `HelmRepository` emitted by `#Bundle` from the chart the releases name                                                                |
| `common-sync-patch`                        | `#Tier.sync`, which generates the level-3 `Kustomization`s rather than patching them                                                    |
| `namespace-cert`, `namespace-cert-kanidm`  | `#NamespaceCert`, switched on with `#Bundle.namespaceCert`. Taking the namespace as a parameter retires the kustomize#5953 duplication. |
| `common-kustomizeconfig`                   | Nothing. It teaches kustomize to chase name references; CUE has no such indirection to teach.                                           |
| `blocky`/`komga` `kustomization-hack.yaml` | `#ConfigMapFiles`, whose stable name leaves nothing to chase                                                                            |

Both `PLACEHOLDER` mechanisms go with it — `namespace` is an ordinary field, and the middleware annotation is computed by `#Release`.

**A content edit does not roll pods.** This is the cost of the stable name. `configMapGenerator` renamed a ConfigMap on every edit and `common-kustomizeconfig` chased the new name into `spec.values`, so the HelmRelease changed and Helm rolled the workload. `#ConfigMapFiles` and the secret manifests keep one name forever, so editing `files/config.yml` or a credential changes only that object — the HelmRelease is untouched and nothing restarts. Worse where the mount uses `subPath` (komga, recyclarr), because kubelet never refreshes those files at all. Restart the workload by hand after such an edit.

# The schema

`#Release` is a HelmRelease with the chart as a parameter (`chart`, `version`, `sourceKind`, `sourceName`), because most of the fleet outside `apps/` runs a foreign chart. `#AppRelease` embeds it and adds what the bjw-s app-template needs: the chart name, the identifier suffix, and the keyed `values.ingress.<key>` the middleware annotations are placed into. A foreign chart splices `ingressAnnotations` at whatever path its own schema uses.

The annotations come from `#IngressAnnotations`, which derives the middleware reference from the namespace it is handed — that is what stops an ingress from naming another namespace's middleware. It is a separate definition because nextcloud has two ingresses behind different middleware sets. It always writes the `router.tls` and `router.entrypoints` annotations: no chart in the fleet supplies them itself.

`#Release.crds` switches on the `install`/`upgrade` block every CRD-shipping chart carries — `crds: CreateReplace` with three remediation retries, byte-identical across the ten releases that have it. `#Release.postRenderers` passes kustomize patches through to the HelmRelease, for what a chart exposes no knob for — opencloud mounts the private CA bundle that way. `#GitRepo` takes `branch` or `tag` plus an optional `ignore`, because two of the three git-sourced charts pin a tag and ship one directory out of a whole repository.

`#Bundle` takes `middlewares` (off where there is no ingress), `namespaceCert` (an in-cluster certificate off the private CA, for a workload that serves TLS to Traefik rather than plain HTTP), `repositories` (defaulting to the bjw-s one, replaced by a bundle on a foreign chart) and `namespaceLabels` (Pod Security admission).

`#AlloyPipeline` is the same shape for logs: it takes a workload's `.alloy` file and emits both the ConfigMap the alloy sidecar collects and the `logs.vonarx.online/pipeline` label the workload's pods have to carry, because a pipeline that claims pods no pod claims back is silently dead. See [observability](/platform/observability.md).

`#VolsyncRestic` takes the SOPS manifest holding its credential Secret as an input — `<workload>/secrets/restic.secret.yaml`, which carries restic credentials and nothing else — so a [backup](/platform/backup-and-restore.md) and the credential it cannot run without are declared together. It exposes the `<app>-restic-<vol>` name that manifest and the `ReplicationSource` have to agree on. `#Bundle.secretFiles` is derived from it — the backups' files plus `extraSecretFiles`, deduplicated through a struct, because a workload usually keeps its restic credential in the same file as its other Secrets. CUE holds the path and never the ciphertext, so it can force the credential to be _named_ and its file shipped, but nothing confirms the file contains it.

**No release takes its values from a Secret.** `spec.valuesFrom` merges the payload into the release, so the material stops being a Secret the moment the chart renders — loki's S3 credentials landed in a plain `ConfigMap` that way. Every workload uses its chart's own mechanism instead: `secretKeyRef` and `envFrom` where the chart offers them, pgadmin's `existingSecret`, and for loki `-config.expand-env=true` with the credentials injected per component. `#Release` carries no field for the old shape, so a bundle cannot reintroduce it.

`#Reserved` holds the one node taint and the three shapes that answer it — an `Exists` toleration, an `Equal` one, and the taint string longhorn takes instead of a pod-spec toleration. `#MediaData` is the NFS export the media tier reads, declared open so a workload can add its own mounts. `#PodCIDR` and `#ServiceCIDR` are the cluster's own networks, named once because a workload that trusts the reverse proxy or firewalls its egress has to repeat them. All exist to keep a cluster address out of many files; see [the cluster](/platform/cluster-nyx.md).

Exceptions are named definitions rather than softened constraints, so `grep` finds every one: `#HardenedWritableRoot` for a container that cannot run on a read-only root, and `#HardenedPrivileged` for one that must run privileged — Kubernetes rejects `privileged: true` together with `allowPrivilegeEscalation: false`, so that definition drops the field rather than the constraint. Both are policy. There are no others: a workload that would need one is a workload that has to change.

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

`nix build .#cue-render-<tier>` runs the same command hermetically and lands `<tree>/<tier>` at `$out`, so the derivation output is itself an artifact root and [the publish workflow](/workflows/images-and-ci.md) needs no path surgery. Each tier's source is `cue.mod`, `schema/` and its own directory — nothing imports across a tier boundary — so editing one workload rebuilds one tier. Its `checkPhase` asserts the rendered subtree holds `sync/` before anything is installed, because a render that lost that subtree still produces a pushable artifact — one that reconciles as an empty tier and prunes the workloads in it.

A flake source is the git tree, so an unstaged new file is invisible to `nix build` while `cue cmd` in the working directory sees it. Adding a `files/` entry and building fails as `@embed: open files/<name>: no such file or directory` until it is `git add`ed.

The sync manifests sit in `sync/` rather than at the artifact root because
[a generated kustomization walks subdirectories](/architecture/flux-topology.md).
`#Tier.sync` generates them, which is what retires `common-sync-patch`: interval,
timeout, prune, `sourceRef` and `decryption` were that component's entire content.

Secrets are copied with `tool/file.Read` into `tool/file.Create`. That is not the
thing the rules forbid — what is forbidden is `@embed` on a SOPS file, which puts
ciphertext into a `.cue` file and reproduces the shape `forbid_secrets` rejects.
The copy happens at command time, lands in no source file, and decrypts nothing.

A workload's plaintext files and SOPS secrets live in its own package; [secrets and SOPS](/workflows/secrets-sops.md) has the naming rule each file has to match.

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
| A disjunction discards bottom branches                                               | "This must be rejected" is expressible in CUE, so the schema's own tests are `cue vet` input rather than a shell harness. `probe/#Verdict` is the idiom.                  |
| `cue vet` without `-c` reports incompleteness without naming the field               | `checks.cueVet` and the docs use `-c`. A container that never sets a hardening field is incomplete, not conflicting, so `-c=false` misses it entirely.                    |

# Open

The rendered bytes depend on the `cue` version, which comes unpinned from nixpkgs: 0.16.1 and 0.17.1 order YAML keys differently, so a `flake.lock` bump republishes every tier without changing any resource.
