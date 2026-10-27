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

`timeout` is the ceiling on the health assessment and defaults to 5m, or 15m where the bundle waits. Two bundles need more: `certs-config` takes 40m because ACME validates the apex and the wildcard sequentially, and `longhorn` 35m to stay above its own release timeout while a DaemonSet rolls across four nodes.

# What an edge means

**Eleven of the twelve providers set `wait: true`, so an edge to one of them means its chart is installed and its pods are up.** `disableWait` defaults to false, so helm-controller has already waited for the chart's resources before the HelmRelease goes Ready, and a bundle's inventory is just the Namespace, its sources, its HelmReleases and its Middleware set — assessing that inventory is therefore the gate a consumer wants, for one boolean. It also closes the webhook race that a plain edge never could: six admission webhooks are live, and applying a `Certificate` or `Cluster` against one with no endpoints fails.

`certs-config` waits on its whole inventory rather than on named objects — root CA cert and Issuer, intermediate cert and ClusterIssuer, the ACME ClusterIssuer and the wildcard all carry a real `Ready`. `metallb-config` is the one provider that waits on nothing, because an `IPAddressPool` has no status to assess.

**The fleet uses no `healthChecks`.** Flux ignores them when `wait` is set, and `wait` covers strictly more, so a second mechanism would only invite a bundle to declare both. `healthCheckExprs` — CEL per GVK, evaluated under `wait` — is the escape hatch for a CR whose conditions kstatus cannot read, and is deliberately unused: the fleet's one such object is the trust-manager `Bundle`, whose status carries only `Synced` and no top-level `observedGeneration`, and nothing waits on it. Its CA reaches kanidm and opencloud as a reflector-copied Secret, so a missing one leaves a pod in `ContainerCreating` rather than failing an apply — [runtime coupling](/platform/certificates-and-pki.md), the same category as a StorageClass.

`wait: true` is never set on an app. A gate on a leaf helps nobody, and cnpg's `Cluster` carries a real `Ready` — so waiting on servarr would mean waiting on a barman restore.

**An edge to a config bundle still only means "applied".** `longhorn-config → longhorn` used to show that limit; it no longer does, because waiting on longhorn also assesses the two `snapshot-crds`/`snapshot-controller` Kustomizations in its `after`, which is where the `VolumeSnapshotClass` CRD comes from. What remains applied-only is an edge to `metallb-config`, and every edge between apps.

A `no matches for kind` message therefore still happens, and it outlives its cause: kustomize-controller's discovery cache keeps failing the dry-run for a while after the CRD is established, so the fix is a reconcile rather than more waiting. Compare the CRD's `creationTimestamp` with the condition's `lastTransitionTime` before believing the message.

Forcing the whole set is one command, and repeating it walks the graph as fast as the CRDs establish:

```sh
kubectl annotate kustomization -n flux-system --all \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

# Traps

- **A `wait` on a bundle whose inventory holds a CR kstatus cannot read is unproven.** kstatus assesses a custom resource generically: top-level `observedGeneration`, then `Reconciling`/`Stalled`. An object with none of those — the trust-manager `Bundle` is the fleet's only one — depends on what that fallback does with nothing to read, and it has not been observed here either way. If a waiting bundle ever sits `Progressing` with every named object Ready, that is the cause, and the fix is a `healthCheckExprs` entry for the GVK rather than dropping the wait.
- **Nothing detects a cycle.** Whether kustomize-controller reports one or merely stalls every node in it is unverified, and CUE will not catch it either — `_provider` is a flat map, and the graph only exists once rendered. A new `needs` is therefore checked by topologically sorting the rendered `sync/*-sync.yaml`, not by `cue vet`. This document is the guard.
- **Two near-misses are live.** `garage → kube-prometheus-stack` means KPS must never need `object-storage` — putting Thanos on Garage would close it. `longhorn → traefik` means Traefik must never need `block-storage`, which is why the default StorageClass is not a capability.
- **A capability with two providers is not expressible.** One name, one bundle. Two bundles providing the same CRD would need the consumers to pick, which the enum deliberately does not allow.
- **Adding a capability to `#Bundle`'s inferred set adds edges everywhere at once.** `middlewares` is on by default, so the 15 `ingress` edges include bundles that render a Middleware set they never reference — `kube-prometheus-stack` serves no ingress of its own. The edge is real either way, because the CR is applied.
