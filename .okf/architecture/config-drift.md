---
type: Register
title: Known configuration drift
description: Six deployed manifests that diverge from the convention the rest of the fleet follows, each surfaced by the CUE migration's fidelity gate.
tags: [drift, conventions, migration]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-06T15:10:00Z }
---

Every entry below is reproduced verbatim by [the CUE tree](/architecture/cue-layout.md), because [the fidelity gate](/decisions/replace-kustomize-with-cue.md) compares against what is deployed rather than against what the conventions say. Correcting one changes the running cluster, so each is its own change.

- **qbittorrent's ingress skips the middleware chain.** It names `qbittorrent-network-internal-whitelist@kubernetescrd` — the bare IP allowlist — where [every other ingress](/platform/networking-and-ingress.md) names one of the three chains. It therefore gets no rate limit, no secure headers and no compression.
- **dedicated-server-abiotic-factor has no `ReplicationDestination`.** Its `saved` volume ships only `source-saved`, so restoring means writing the resource by hand rather than [flipping `enabled`](/platform/backup-and-restore.md).
- **openaudible's two volsync movers disagree.** `source-config` sets `fsGroupChangePolicy: OnRootMismatch` in its `moverSecurityContext`; `dest-config` does not.
- **`UMASK` is written two ways.** jellyfin, qbittorrent and the three `*arr` apps quote it (`"0002"`); audiobookshelf, komga and openaudible do not, and YAML renders an unquoted `0002` as the integer `2`. Both mean the same mask, because umask parses octal.
- **Two MetalLB annotation domains are in use.** jellyfin pins its address with `metallb.universe.tf/loadBalancerIPs`, dedicated-server-abiotic-factor with `metallb.io/loadBalancerIPs`. Both are honoured; only the first is [the documented one](/platform/networking-and-ingress.md).
- **nextcloud's `HelmRepository` declares a namespace that is discarded.** The file says `flux-system` and the build emits `nextcloud`, because kustomize's `namespace:` directive rewrites it.

Three fields in the CUE schema exist only to reproduce the first three — `bareMiddleware`, `#VolsyncRestic.restore` and `#VolsyncRestic.sourceMoverExtra`. Each names one workload in its comment, and each goes away with the drift it models.
