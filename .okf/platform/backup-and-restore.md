---
type: Playbook
title: Backup and restore
description: The two independent backup systems — volsync/restic for PVCs and CNPG/barman-cloud for Postgres — and the manual steps each restore requires.
tags: [volsync, restic, cnpg, barman, backup, disaster-recovery]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-07T19:30:00Z }
---

Both systems push off-cluster to third-party S3. Nothing is backed up into [Garage](/platform/storage.md).

# volsync + restic (PVC data)

A backed-up app declares two objects in its HelmRelease `rawResources`, following the naming `source-<volume>` / `dest-<volume>`:

|               | `source-<vol>`                             | `dest-<vol>`             |
| ------------- | ------------------------------------------ | ------------------------ |
| Kind          | `ReplicationSource`                        | `ReplicationDestination` |
| `enabled`     | `true`                                     | **`false`**              |
| Trigger       | `schedule: "@daily"`                       | `manual: restore-once`   |
| `copyMethod`  | `Clone`                                    | `Snapshot`               |
| Storage class | `longhorn-local-lax` (cache on `longhorn`) | `longhorn`               |
| Retention     | 7 daily / 4 weekly, prune every 7d         | —                        |

The PVC references the destination through `dataSourceRef`, and the mover runs under the app's `&PUID`/`&GUID` anchors so restored files keep their ownership.

**Restore is deliberately two-step and manual.** The destination ships disabled, so a normal reconcile never restores. To recover: set `dest-<vol>.enabled: true`, let the destination populate a snapshot, then let the PVC bind from it. Leaving it enabled afterwards is the failure mode to watch for.

`dataSourceRef` is immutable once the PVC exists, so a volume that ships without one can never gain it by reconcile — the PVC has to be recreated. Every backed-up volume therefore declares it up front, whether or not a restore is ever wanted.

Repository credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) live in a per-app, per-volume Secret named `<app>-restic-<vol>`, delivered by either [secret shape](/architecture/app-template-pattern.md). Nothing ties the two together here: the name is written twice and a backup whose Secret is missing fails on its first scheduled run. [The CUE tree](/architecture/cue-layout.md) makes the credential an input of the backup instead.

# CNPG + barman-cloud (Postgres)

The plugin is a HelmRelease of its own in the `cnpg` namespace, `plugin-barman-cloud` from the same chart repository the operator comes from. The operator finds it by the `cnpg.io/pluginName` label on its `Service`, not by the release name.

`apps/base/servarr/manifests/cnpg/` is the reference shape; blocky, gotify and nextcloud follow it in miniature.

- **`ObjectStore`** (`barmancloud.cnpg.io/v1`) named `storj` — `s3://k8s-cnpg-backup` at `https://gateway.storjshare.io`, 30d retention, gzip WAL, credentials from `backup-s3-credentials`.
- **`Cluster`** — three instances with required pod anti-affinity, storage and WAL on `longhorn-local-strict`, and the `barman-cloud.cloudnative-pg.io` plugin as `isWALArchiver`.
- **`ScheduledBackup`** for base backups.
- **Roles are declared, not created by hand**: `spec.managed.roles` lists each consumer with its own `passwordSecret`, one Secret per app.

Clusters bootstrap from `recovery`, not `initdb` — `spec.bootstrap.recovery.source` names an `externalClusters` entry pointing back at the object store. A cluster recreated from scratch therefore restores rather than starting empty.

Postgres images come from upstream: `infrastructure/nyx/config/cnpg` syncs the `image-catalogs/` directory of `github.com/cloudnative-pg/artifacts` through its own `GitRepository`, and clusters reference `ClusterImageCatalog` `postgresql-standard-trixie` by major version rather than pinning an image tag.

# Traps

- The `ObjectStore` sets `AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` to `when_required` in `instanceSidecarConfiguration`. This is a compatibility workaround for non-AWS S3 ([plugin-barman-cloud#541](https://github.com/cloudnative-pg/plugin-barman-cloud/issues/541)); removing it breaks Storj.
- The archiving `serverName` (`servarr-cnpg`) and the recovery `serverName` (`servarr-cnpg-restored-5`) are different, hand-maintained strings. The trailing counter is bumped manually per restore generation — a restore does not read from the path the live cluster writes to.
- volsync and CNPG are independent. An app with both a PVC and a database needs both restored, and neither system knows about the other's point in time.
