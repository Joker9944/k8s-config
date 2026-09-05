---
type: Architecture
title: App-template pattern
description: The directory shape, HelmRelease idioms and secret shapes every workload under apps/base and infrastructure/base follows.
tags: [helm, app-template, conventions]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T20:40:00Z }
---

# Directory shape

```
<tree>/base/<name>/
  kustomization.yaml               namespace, resources, components, generators
  manifests/namespace.yaml         metadata.name: PLACEHOLDER
  manifests/secret.yaml            SOPS, data/stringData only
  flux/helm-release.yaml           the HelmRelease
  flux/helm-repository.yaml        only when not using a shared component
  flux/git-repository.yaml         only when the chart lives in a git repo
  values/secret-values.sops.yaml   fully-encrypted values file
  files/<config>                   configMapGenerator source
  kanidm-oidc.txt                  manual OIDC registration commands
  kustomize/kustomization-hack.yaml  per-app kustomize configurations
```

Nesting is allowed: `apps/base/servarr/` is one namespace and one CNPG cluster containing six sub-directories, each with its own `kustomization.yaml` listed under the parent's `resources:`. Sub-directories set no `namespace:` — they inherit it.

# HelmRelease idioms

Almost every workload uses the bjw-s `app-template` chart, pinned by version, with a `# yaml-language-server: $schema=…` first line for editor validation and `global.alwaysAppendIdentifierToResourceName: true`.

- **YAML anchors** carry values reused within one file: `&PUID`/`&GUID` for the pod security context and the volsync mover, `&port_http` for probes and services, `&host` for the ingress rule and its TLS entry, `&pvc_config_size` for the PVC and its `ReplicationDestination`.
- **Hardening is uniform**: `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, with `emptyDir` volumes wherever the app insists on writing.
- **`rawResources`** embeds non-chart objects in the release — used throughout for volsync `ReplicationSource`/`ReplicationDestination` (see [backup and restore](/platform/backup-and-restore.md)) rather than as separate manifests.
- Image tags are pinned by tag **and** digest (`10.11.11@sha256:…`); renovate maintains both.

# Two secret shapes

| Shape    | File                             | Encrypted                | Reaches the workload via                                 |
| -------- | -------------------------------- | ------------------------ | -------------------------------------------------------- |
| Manifest | `manifests/secret.yaml`          | `data`/`stringData` only | applied directly, decrypted by Flux                      |
| Values   | `values/secret-values.sops.yaml` | whole file               | `secretGenerator` → `spec.valuesFrom` on the HelmRelease |

The values shape depends on [`common-kustomizeconfig`](/architecture/kustomize-components.md) so the generated Secret's hash suffix propagates into `valuesFrom`; without it the release references a name that no longer exists. The suffix is also what makes a ciphertext edit reach the workload: the Secret is renamed on every content change, so the HelmRelease changes and Helm upgrades. A stable Secret name would leave that upgrade depending on helm-controller noticing the source change by itself. Details of which rule encrypts what are in [secrets and SOPS](/workflows/secrets-sops.md).

# Chart sources

Most releases pull `app-template` from the shared `bjw-s` `HelmRepository`. Two mount a chart directly out of a `GitRepository` narrowed by an `ignore:` block — garage (`script/helm/garage`, tag-pinned) and opencloud (branch `main`, unpinned). The rest declare a per-app `flux/helm-repository.yaml` for their upstream.

# kanidm-oidc.txt

Nine workloads carry a `kanidm-oidc.txt` beside their manifests holding the literal `kanidm` CLI commands that register the OAuth2 client, redirect URLs, groups and scope maps. **Nothing applies these** — they are a runbook, replayed by hand. See [identity](/platform/identity-kanidm.md).
