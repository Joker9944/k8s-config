---
type: Infrastructure
title: Storage
description: The three Longhorn storage classes and when each is correct, plus the NFS and Garage object storage that sit outside Longhorn.
tags: [longhorn, nfs, garage, s3, storage]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# Longhorn classes

The chart's default `longhorn` class is replicated. `infrastructure/nyx/config/longhorn` adds two single-replica classes, both `allowVolumeExpansion: true`:

| Class                   | `dataLocality` | Replicas | Intended for                                                                                       |
| ----------------------- | -------------- | -------- | -------------------------------------------------------------------------------------------------- |
| `longhorn`              | default        | default  | volsync restore targets and mover caches — data that is transient or already backed up elsewhere   |
| `longhorn-local-strict` | `strict-local` | 1        | data with its own replication above the volume: CNPG instances and their WAL, Garage meta and data |
| `longhorn-local-lax`    | `best-effort`  | 1        | volsync `Clone` sources, where a scheduling failure must not block the backup                      |

The single-replica classes are a deliberate trade: replication is delegated to the application (three CNPG instances with required anti-affinity, Garage's own redundancy) instead of being paid for twice. Putting an app with no replication of its own on `longhorn-local-strict` means one node loss is data loss.

A `VolumeSnapshotClass` named `longhorn` backs volsync's `copyMethod: Snapshot`; see [backup and restore](/platform/backup-and-restore.md).

# NFS

Bulk media is not in Longhorn at all. Workloads mount it straight off the NAS with `type: nfs`, `server: 192.168.0.10`, paths under `/mnt/chronos/`. Nothing in this repo backs it up or provisions it — the NAS is external state.

Pods that read it declare a preferred node affinity on `vonarx.online/nfs-host`, the label carried only by `nyx-worker-1` (see [the cluster](/platform/talos-nyx.md)).

# Garage

Garage is the in-cluster S3, and the whole of the `storage` tier. Its chart is mounted out of the upstream `GitRepository` (`script/helm/garage`, tag-pinned), and it stores meta (6Gi) and data (120Gi) on `longhorn-local-strict`.

- API: `s3.vonarx.online` and `*.s3.vonarx.online`, region `nyx`
- Web: `*.web.vonarx.online`
- In-cluster: `http://garage.garage.svc.cluster.local:3900`

Consumers are Loki (chunks and indexes) and opencloud. Because `loki` `dependsOn` `garage`, Garage is the first thing the observability tier waits on.

Administration is CLI-inside-the-pod; the [dev shell](/workflows/dev-environment.md) defines a `garage` alias that execs into `garage-0`.

Garage is **not** where backups go — those leave the cluster entirely. See [backup and restore](/platform/backup-and-restore.md).
