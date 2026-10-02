---
type: Architecture
title: App-template pattern
description: The bjw-s app-template idioms every workload follows, the chart sources, and the OIDC runbooks that sit beside them.
tags: [helm, app-template, conventions]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-02T12:45:00Z }
---

# Package shape

```
cue/<tree>/<tier>/<name>/
  <name>.cue                 package <name> — the bundle and its releases
  files/<config>             plaintext, read with @embed
  secrets/restic.secret.yaml the volsync credential, and nothing else
  secrets/<name>.secret.yaml everything else the workload reads
  kanidm-oidc.txt            manual OIDC registration commands
```

Nesting is flat: `apps/media/servarr/` is one package holding six releases, one namespace and one CNPG cluster, keyed per sub-app in `secrets/<app>.secret.yaml` and `kanidm-oidc/<app>.txt`. See [the CUE layout](/architecture/cue-layout.md).

# HelmRelease idioms

Almost every workload uses the bjw-s `app-template` chart through `#AppRelease`, which supplies the chart name, the pinned version and `global.alwaysAppendIdentifierToResourceName: true`.

- **Values reused within a release are `let` bindings** — `uid`/`gid` for the pod security context and the volsync mover, `portHTTP` for probes and services, `host` for the ingress rule and its TLS entry, `configSize` for the PVC and its `ReplicationDestination`. These were YAML anchors.
- **Hardening is uniform and enforced by the type checker**: `#Hardened` pins `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]`, with `emptyDir` volumes wherever the app insists on writing.
- **Selkies desktop images set `MAX_RES`** (openaudible). Xvfb's framebuffer is a SysV shm segment charged to the pod cgroup, and the image default of `15360x8640` reserves 506Mi of the memory limit on its own. The IPC namespace belongs to the pod sandbox rather than the container, so a SIGKILLed Xvfb orphans its segment and every restart leaks another — once the cgroup fills, the container OOMs within a second and only deleting the pod clears it.
- **Mounts are `globalMounts` unless a release has more than one container.** `advancedMounts: <controller>: <container>: [...]` says the same thing in three times the text when there is only one place it could land; qbittorrent and servarr earn it, nothing else does.
- **`rawResources`** embeds non-chart objects in the release — volsync pairs (spliced in by `#AppRelease` from `backups`, see [backup and restore](/platform/backup-and-restore.md)), CNPG clusters, Traefik `ServersTransport`. **The chart names each from its key and the release**, so a `metadata.name` written into the manifest is silently overridden — which is why `#VolsyncRestic` sets no `metadata` at all and its objects come out `<app>-source-<vol>`. Pick the key for the name you want.
- Image tags are pinned by tag **and** digest (`10.11.11@sha256:…`), which `#Digest` requires and renovate maintains.

# Secrets

One shape: a SOPS `Secret` manifest with `data`/`stringData` encrypted, listed in the bundle's `secretFiles` and copied verbatim beside the generated manifests. The workload reads it through whatever its chart offers — `secretKeyRef`, `envFrom`, `existingSecret`, a mounted volume. No release takes its values from a Secret. Details of which rule encrypts what are in [secrets and SOPS](/workflows/secrets-sops.md).

# Chart sources

Most releases pull `app-template` from the shared `bjw-s` `HelmRepository`, which `#Bundle.repositories` defaults to. One mounts a chart directly out of a `#GitRepo` narrowed by an `ignore` block — garage (`script/helm/garage`, tag-pinned). The rest declare their upstream as a `#HelmRepo` in the bundle, opencloud's with `type: "oci"`: `opencloud-eu/helm` was archived in favour of a paid offering, and the community fork carrying it on publishes an OCI artifact rather than a chart index.

# kanidm-oidc.txt

Ten workloads carry one, holding the literal `kanidm` CLI commands that register the OAuth2 client, redirect URLs, groups and scope maps. **Nothing applies these** — they are a runbook, replayed by hand. See [identity](/platform/identity-kanidm.md).
