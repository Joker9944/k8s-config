---
type: Infrastructure
title: Storage
description: The three Longhorn storage classes and when each is correct, plus the NFS and Garage object storage that sit outside Longhorn.
tags: [longhorn, nfs, garage, s3, storage]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T09:00:00Z }
---

# Longhorn classes

The chart's default `longhorn` class is replicated. `cue/infrastructure/controllers/longhorn-config` adds two single-replica classes, both `allowVolumeExpansion: true`:

| Class                   | `dataLocality` | Replicas | Intended for                                                                                       |
| ----------------------- | -------------- | -------- | -------------------------------------------------------------------------------------------------- |
| `longhorn`              | default        | default  | volsync restore targets and mover caches — data that is transient or already backed up elsewhere   |
| `longhorn-local-strict` | `strict-local` | 1        | data with its own replication above the volume: CNPG instances and their WAL, Garage meta and data |
| `longhorn-local-lax`    | `best-effort`  | 1        | volsync `Clone` sources, where a scheduling failure must not block the backup                      |

The single-replica classes are a deliberate trade: replication is delegated to the application (three CNPG instances with required anti-affinity, Garage's own redundancy) instead of being paid for twice. Putting an app with no replication of its own on `longhorn-local-strict` means one node loss is data loss.

A `VolumeSnapshotClass` named `longhorn` backs volsync's `copyMethod: Snapshot`; see [backup and restore](/platform/backup-and-restore.md).

# NFS

Bulk media is not in Longhorn at all. Workloads mount it straight off `mother` through [`#MediaData`](/architecture/cue-layout.md) — `type: nfs`, `server: 192.168.0.24`, `/chronos/media-data` — which exists so the address moves in one edit when the host does. The export has no `/mnt` prefix — the pool sets no local mountpoint, and TrueNAS only displayed one because it imported with `altroot=/mnt`. Nothing in this repo backs it up or provisions it; the pool belongs to [nix-config](/platform/cluster-nyx.md).

Only jellyfin declares the preferred `vonarx.online/nfs-host` affinity, because `mother` is reserved and jellyfin is the one media workload that tolerates the taint.

# Garage

Garage is the in-cluster S3, and the whole of the `storage` tier. Its chart is mounted out of the upstream `GitRepository` (`script/helm/garage`, tag-pinned), and it stores meta (6Gi) and data (120Gi) on `longhorn-local-strict`.

- API: `s3.vonarx.online` and `*.s3.vonarx.online`, region `nyx`
- Web: `*.web.vonarx.online`
- In-cluster: `http://garage.garage.svc.cluster.local:3900`

Consumers are Loki (chunks and indexes) and opencloud. Because `loki` `dependsOn` `garage`, Garage is the first thing the observability tier waits on.

Administration is CLI-inside-the-pod; the [dev shell](/workflows/dev-environment.md) defines a `garage` alias that execs into `garage-0`.

Garage is **not** where backups go — those leave the cluster entirely. See [backup and restore](/platform/backup-and-restore.md).
