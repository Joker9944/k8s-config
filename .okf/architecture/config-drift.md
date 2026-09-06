---
type: Register
title: Known configuration drift
description: Deployed manifests that diverge from the convention the rest of the fleet follows, each surfaced by the CUE migration's fidelity gate.
tags: [drift, conventions, migration]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-06T18:40:00Z }
---

Every entry below is reproduced verbatim by [the CUE tree](/architecture/cue-layout.md), because [the fidelity gate](/decisions/replace-kustomize-with-cue.md) compares against what is deployed rather than against what the conventions say. Correcting one changes the running cluster, so each is its own change.

- **qbittorrent's ingress skips the middleware chain.** It names `qbittorrent-network-internal-whitelist@kubernetescrd` — the bare IP allowlist — where [every other ingress](/platform/networking-and-ingress.md) names one of the three chains. It therefore gets no rate limit, no secure headers and no compression.
- **dedicated-server-abiotic-factor has no `ReplicationDestination`.** Its `saved` volume ships only `source-saved`, so restoring means writing the resource by hand rather than [flipping `enabled`](/platform/backup-and-restore.md).
- **openaudible's two volsync movers disagree.** `source-config` sets `fsGroupChangePolicy: OnRootMismatch` in its `moverSecurityContext`; `dest-config` does not.
- **`UMASK` is written two ways.** jellyfin, qbittorrent and the three `*arr` apps quote it (`"0002"`); audiobookshelf, komga and openaudible do not, and YAML renders an unquoted `0002` as the integer `2`. Both mean the same mask, because umask parses octal.
- **Two MetalLB annotation domains are in use.** jellyfin pins its address with `metallb.universe.tf/loadBalancerIPs`, dedicated-server-abiotic-factor with `metallb.io/loadBalancerIPs`. Both are honoured; only the first is [the documented one](/platform/networking-and-ingress.md).
- **nextcloud's `HelmRepository` declares a namespace that is discarded.** The file says `flux-system` and the build emits `nextcloud`, because kustomize's `namespace:` directive rewrites it. metallb's `IPAddressPool` and `L2Advertisement` do the same thing, declaring `metallb` against a `metallb-system` namespace.
- **gotify's PVC is not backed up.** Its `source-data` `ReplicationSource` is `enabled: false` and the `dataSourceRef` on the volume is commented out, so a lost volume has nothing to restore from. Every other backed-up volume in the fleet [runs its source](/platform/backup-and-restore.md).
- **kube-prometheus-stack's Grafana and Prometheus TLS hosts are doubled.** Both name `<app>.vonarx.online.vonarx.online` under `ingress.tls[].hosts`; alertmanager, on the same chart, is correct. The wildcard certificate covers the routers regardless, which is why nothing ever failed.
- **traefik-geo-lookup is the only app-template release without the identifier suffix.** Every other one sets `global.alwaysAppendIdentifierToResourceName`. Turning it on renames its Deployment and Service, so the exception costs a rollout.
- **alloy's `HelmRepository` declares a Flux post-build variable.** `namespace: ${app_namespace:=alloy}` never reaches Flux — kustomize's `namespace:` directive overwrites it first — and nothing in the repository sets `postBuild.substitute` for it to resolve against.

Five fields in the CUE schema exist only to reproduce entries above — `bareMiddleware`, `identifierSuffix`, `#VolsyncRestic.restore`, `#VolsyncRestic.sourceMoverExtra` and `#VolsyncRestic.enabled`. Each names one workload in its comment, and each goes away with the drift it models.
