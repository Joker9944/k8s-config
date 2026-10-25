---
type: Architecture
title: Capability graph
description: How level-3 ordering is derived from capability declarations, the chains that result, and the cycles that must not be closed.
tags: [gitops, flux, dependencies, ordering]
resource: cue/schema/bundle.cue
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-25T00:00:00Z }
---

All ordering in the fleet lives in the level-3 Kustomizations described by [Flux topology](/architecture/flux-topology.md). They all sit in `flux-system` and name each other by plain string, so the graph is global and tier-blind: a tier decides which artifact a workload ships in, nothing more. `loki → garage` crosses tiers, and `volsync → kube-prometheus-stack` runs against the direction the old level-2 graph implied.

# A capability, not a bundle name

A consumer declares what it needs, never who provides it. `#Capability` is a closed enum and `_provider` maps each entry to exactly one bundle name, so a typo is a build error rather than a Kustomization waiting forever on a name nobody owns, and a provider can be renamed or moved tiers without touching a consumer.

| Capability            | Provider                                              | What the consumer cannot apply without it                      |
| --------------------- | ----------------------------------------------------- | -------------------------------------------------------------- |
| `ingress`             | [`traefik`](/platform/networking-and-ingress.md)      | `Middleware`                                                   |
| `certificate`         | [`cert-manager`](/platform/certificates-and-pki.md)   | `Certificate`                                                  |
| `ingress-certificate` | [`certs-config`](/platform/certificates-and-pki.md)   | the wildcard cert and intermediate CA Traefik serves           |
| `load-balancer`       | `metallb`                                             | `IPAddressPool`, `L2Advertisement`                             |
| `load-balancer-pool`  | `metallb-config`                                      | the pool Traefik's Service draws an address from               |
| `redis`               | `redis-operator`                                      | the ot-helm redis chart's CR                                   |
| `block-storage`       | [`longhorn`](/platform/storage.md)                    | `VolumeSnapshotClass`, via the Kustomizations longhorn creates |
| `postgres`            | [`cnpg`](/platform/backup-and-restore.md)             | `Cluster`, `ObjectStore`                                       |
| `volsync`             | [`volsync`](/platform/backup-and-restore.md)          | `ReplicationSource`, `ReplicationDestination`                  |
| `monitoring`          | [`kube-prometheus-stack`](/platform/observability.md) | `ServiceMonitor`, and the scrape classes one names             |
| `object-storage`      | [`garage`](/platform/storage.md)                      | the S3 endpoint                                                |
| `log-sink`            | [`loki`](/platform/observability.md)                  | the push endpoint                                              |

**A capability is something whose absence fails the apply, which in practice means a CRD.** Runtime coupling is not a capability: a PVC naming a StorageClass that does not exist yet stays `Pending` and binds later, so storage classes are deliberately absent from the enum. Declaring them would also close a cycle — `traefik`'s OIDC Redis volumes are on the default `longhorn` class, and longhorn's own bundle needs `ingress`.

# Three edges derive themselves

The three highest-fan-in capabilities are inferred from fields [`#Bundle`](/architecture/cue-layout.md) already carries and are never written:

| Field                         | Implies       |
| ----------------------------- | ------------- |
| `middlewares` (on by default) | `ingress`     |
| `namespaceCert`               | `certificate` |
| any release with `backups`    | `volsync`     |

Everything else is an explicit `needs`, because the fact lives in chart values CUE cannot introspect — it sees a HelmRelease, never what the chart renders. A `ServiceMonitor` is spelled `monitoring.metrics.serviceMonitor.enabled` in garage, `monitoring.enabled` in opencloud, and a `.Capabilities` gate in volsync's chart; there is no uniform field to read.

A provider needing its own capability is filtered in `#Tier.sync`, which is the only place a bundle's own name is known — `bundles` is keyed by it.

# The graph

Acyclic: 32 bundles, 42 edges, six levels. Derived by topologically sorting the rendered manifests, which is the only form of the graph that is authoritative.

```
L0  cert-manager  cnpg  metallb  redis-operator  reflector  reloader
    generic-device-plugin  nvidia-device-plugin
L1  blocky  certs-config  cnpg-config  metallb-config
L2  traefik
L3  kube-prometheus-stack  longhorn  nextcloud  pgadmin  servarr
L4  garage  longhorn-config  opencloud  volsync
L5  audiobookshelf  gotify  jellyfin  jellyseerr  kanidm  komga  loki
    openaudible  qbittorrent
L6  alloy
```

The two chains that set the depth:

- `cert-manager → certs-config → traefik → kube-prometheus-stack → volsync`
- `cert-manager → certs-config → traefik → kube-prometheus-stack → garage → loki → alloy`

`traefik` at L2 is the fleet's articulation point: 15 bundles reach it through `ingress` alone, and everything above L2 is behind it.

Level-3 Kustomizations carry `retryInterval: "1m"` against a 10m `interval`. Without it a blocked reconcile retries at the interval, so a six-hop chain costs an hour of waiting rather than six minutes.

# What an edge still does not buy

**An edge is satisfied when the other bundle's manifests apply, not when its controller runs.** A bundle whose content is a HelmRelease goes Ready as soon as that object exists, so the chart may not have installed and its CRDs may not be established. `healthChecks` are the only thing that closes the gap, and `certs-config` is the only bundle using them — which is why `traefik → certs-config` is the one edge in the fleet that genuinely waits for a working controller. Every other one of the 42 means "applied".

`longhorn-config → longhorn` shows the limit: the `VolumeSnapshotClass` CRD it needs comes from `snapshot-crds` and `snapshot-controller`, two Kustomizations the longhorn bundle _creates_, so the edge is satisfied the moment those objects are applied — long before they have reconciled anything.

A `no matches for kind` message therefore still happens, and it outlives its cause: kustomize-controller's discovery cache keeps failing the dry-run for a while after the CRD is established, so the fix is a reconcile rather than more waiting. Compare the CRD's `creationTimestamp` with the condition's `lastTransitionTime` before believing the message.

Forcing the whole set is one command, and repeating it walks the graph as fast as the CRDs establish:

```sh
kubectl annotate kustomization -n flux-system --all \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

# Traps

- **Nothing detects a cycle.** Whether kustomize-controller reports one or merely stalls every node in it is unverified, and CUE will not catch it either — `_provider` is a flat map, and the graph only exists once rendered. A new `needs` is therefore checked by topologically sorting the rendered `sync/*-sync.yaml`, not by `cue vet`. This document is the guard.
- **Two near-misses are live.** `garage → kube-prometheus-stack` means KPS must never need `object-storage` — putting Thanos on Garage would close it. `longhorn → traefik` means Traefik must never need `block-storage`, which is why the default StorageClass is not a capability.
- **A capability with two providers is not expressible.** One name, one bundle. Two bundles providing the same CRD would need the consumers to pick, which the enum deliberately does not allow.
- **Adding a capability to `#Bundle`'s inferred set adds edges everywhere at once.** `middlewares` is on by default, so the 15 `ingress` edges include bundles that render a Middleware set they never reference — `kube-prometheus-stack` serves no ingress of its own. The edge is real either way, because the CR is applied.
