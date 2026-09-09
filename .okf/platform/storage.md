---
type: Infrastructure
title: Storage
description: The three Longhorn storage classes and when each is correct, plus the NFS and Garage object storage that sit outside Longhorn.
tags: [longhorn, nfs, garage, s3, storage]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T10:35:00Z }
---

# Longhorn classes

The chart's default `longhorn` class is replicated. `cue/infrastructure/controllers/longhorn-config` adds two single-replica classes, both `allowVolumeExpansion: true`:

| Class                   | `dataLocality` | Replicas | Intended for                                                                                                                                  |
| ----------------------- | -------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `longhorn`              | default        | default  | volsync restore targets and mover caches — data that is transient or already backed up elsewhere                                              |
| `longhorn-local-strict` | `strict-local` | 1        | data with its own replication above the volume: CNPG instances and their WAL, Garage meta and data, Loki's ingester WAL and compactor scratch |
| `longhorn-local-lax`    | `best-effort`  | 1        | volsync `Clone` sources, where a scheduling failure must not block the backup                                                                 |

The single-replica classes are a deliberate trade: replication is delegated to the application (three CNPG instances with required anti-affinity, Garage's own redundancy, Loki's `replication_factor: 3`) instead of being paid for twice. Putting an app with no replication of its own on `longhorn-local-strict` means one node loss is data loss.

Longhorn schedules against reserved size, never used size, and `storage-over-provisioning-percentage` is 100 against a `storageReserved` of 0 — so each node's ceiling is its whole disk, and `spec.size × numberOfReplicas` counts against it from the moment a volume exists, however empty it stays. A claim size is therefore a capacity decision rather than a limit, and the chart default is rarely the right one. `strict-local` sharpens this: its replica is placed when the pod attaches, not when the PVC binds, so an oversized volume provisions cleanly and only fails once its pod lands on a node without room. `mother`'s headroom is reachable only by replicated volumes, since Longhorn tolerates its `reserved=storage` taint but [almost no workload does](/platform/cluster-nyx.md).

A `VolumeSnapshotClass` named `longhorn` backs volsync's `copyMethod: Snapshot`; see [backup and restore](/platform/backup-and-restore.md).

# NFS

Bulk media is not in Longhorn at all. Workloads mount it straight off `mother` through [`#MediaData`](/architecture/cue-layout.md) — `type: nfs`, `server: 192.168.0.24`, `/chronos/media-data` — which exists so the address moves in one edit when the host does. The export has no `/mnt` prefix — the pool sets no local mountpoint, and TrueNAS only displayed one because it imported with `altroot=/mnt`. Nothing in this repo backs it up or provisions it; the pool belongs to [nix-config](/platform/cluster-nyx.md).

Only jellyfin declares the preferred `vonarx.online/nfs-host` affinity, because `mother` is reserved and jellyfin is the one media workload that tolerates the taint.

# Garage

Garage is the in-cluster S3, and the whole of the `storage` tier. Its chart is mounted out of the upstream `GitRepository` (`script/helm/garage`, tag-pinned), and it stores meta (6Gi) and data (120Gi) on `longhorn-local-strict`.

- API: `s3.vonarx.online` and `*.s3.vonarx.online`, region `nyx`
- Web: `*.web.vonarx.online`
- In-cluster: `http://garage.garage.svc.cluster.local:3900`

Consumers are Loki (chunks and indexes), nextcloud and opencloud. nextcloud uses it as _primary_ object storage, so user files and previews never reach Longhorn — its volume holds only the ~900MB server tree, `config/` and `custom_apps/`, and the chart's separate data PVC is redundant. Because `loki` `dependsOn` `garage`, Garage is the first thing the observability tier waits on.

Administration is CLI-inside-the-pod; the [dev shell](/workflows/dev-environment.md) defines a `garage` alias that execs into `garage-0`.

Garage is **not** where backups go — those leave the cluster entirely. See [backup and restore](/platform/backup-and-restore.md).
