---
type: Playbook
title: Backup and restore
description: The backup systems — volsync/restic for PVCs, CNPG/barman-cloud for Postgres, opencloud's orchestrated CronJob — and the manual steps each restore requires.
tags: [volsync, restic, cnpg, barman, rclone, backup, disaster-recovery]
status: stable
generated: { by: claude-code/fable-5, at: 2026-09-12T01:00:00Z }
---

Both systems push off-cluster to third-party S3. Nothing is backed up into [Garage](/platform/storage.md).

# volsync + restic (PVC data)

A backed-up app declares a `#VolsyncRestic`, which emits two objects into the release's `rawResources` under the names `source-<volume>` / `dest-<volume>`. A foreign-chart release has no `rawResources`: it sets `ns`, which puts `metadata` on the manifests, and places them in the bundle's `before` itself — opencloud is the only one.

|               | `source-<vol>`                             | `dest-<vol>`             |
| ------------- | ------------------------------------------ | ------------------------ |
| Kind          | `ReplicationSource`                        | `ReplicationDestination` |
| `enabled`     | `true`                                     | **`false`**              |
| Trigger       | `schedule: "@daily"`                       | `manual: restore-once`   |
| `copyMethod`  | `Clone`                                    | `Snapshot`               |
| Storage class | `longhorn-local-lax` (cache on `longhorn`) | `longhorn`               |
| Retention     | 7 daily / 4 weekly, prune every 7d         | —                        |

The PVC references the destination through `dataSourceRef`, and the mover runs under the app's own uid/gid so restored files keep their ownership.

**Restore is deliberately two-step and manual.** The destination normally ships disabled, so a reconcile never restores by itself. To recover: set `dest-<vol>.enabled: true`, let the destination populate a snapshot, then let the PVC bind from it. Leaving it enabled afterwards is the failure mode to watch for — the manual trigger fires once, but a PVC recreated later restores from that stale snapshot instead of starting empty.

`dataSourceRef` is immutable once the PVC exists, so a volume that ships without one can never gain it by reconcile — the PVC has to be recreated. Every backed-up volume therefore declares it up front, whether or not a restore is ever wanted.

Repository credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) live in a per-app, per-volume Secret named `<app>-restic-<vol>`. The file holding it is an input of [`#VolsyncRestic`](/architecture/cue-layout.md) — `<workload>/secrets/restic.secret.yaml` — so a backup and the credential it cannot run without are declared together. CUE never reads ciphertext, so nothing checks the other half — that the named file really holds the Secret. A missing credential surfaces only on the first scheduled run.

# Orchestrated backup (opencloud)

`decomposeds3` splits every file between the data PVC and Garage (see [storage](/platform/storage.md)), and upstream recommends the server be off during backup. One nightly CronJob — `opencloud-backup`, `cue/apps/cloud/opencloud/backup.cue` plus `files/backup.py` — therefore captures both halves inside a single quiesce window: scale the Deployment to 0, patch the `ReplicationSource`'s `spec.trigger.manual` with a timestamp, `rclone sync` the bucket to the off-cluster repository, wait for `status.lastManualSync`, and scale back up through an EXIT trap so a failure never leaves the app down. The stock `KubeJobFailed`/`KubeJobNotCompleted` rules alert on it; there is deliberately no `activeDeadlineSeconds`, which would kill the pod before the trap.

- A manual trigger supersedes the `@daily` schedule for as long as it is set, and Flux's SSA never owned `spec.trigger.manual`, so reconciles do not strip it. The schedule only ever fires between first apply and the CronJob's first run.
- The chart's own claim has no `dataSourceRef` knob, so the PVC (`opencloud-data`) is declared in the bundle and handed to the chart via `existingClaim`. Kustomize prune applies: the PVC leaving git deletes the volume.
- The bucket mirror lives under `<bucket>/opencloud/blobs`: `current/` is the sync target, and anything sync would delete or overwrite moves into `deleted/<ts>/`, pruned after 28 days **by directory name**. Not `--min-age` — server-side copies keep original modtimes, so an old-but-freshly-deleted blob would be purged from the graveyard immediately.
- Restore is two restores from the same nightly run. PVC: set `_restore: true` in `backup.cue` so the `ReplicationDestination` exists, then the normal two-step flow above. Bucket: reverse the sync — `rclone sync dst:…/current src:opencloud` — pulling anything needed out of `deleted/<ts>/` first.

# CNPG + barman-cloud (Postgres)

The plugin is a HelmRelease of its own in the `cnpg` namespace, `plugin-barman-cloud` from the same chart repository the operator comes from. The operator finds it by the `cnpg.io/pluginName` label on its `Service`, not by the release name.

`cue/apps/media/servarr` is the only workload that backs Postgres up, through four objects:

- **`ObjectStore`** (`barmancloud.cnpg.io/v1`) named `storj` — `s3://k8s-cnpg-backup` at `https://gateway.storjshare.io`, 30d retention, gzip WAL, credentials from `backup-s3-credentials`.
- **`Cluster`** — three instances with required pod anti-affinity, storage and WAL on `longhorn-local-strict`, and the `barman-cloud.cloudnative-pg.io` plugin as `isWALArchiver`.
- **`ScheduledBackup`** for base backups.
- **Roles are declared, not created by hand**: `spec.managed.roles` lists each consumer with its own `passwordSecret`, one Secret per app.

Its cluster bootstraps from `recovery`, not `initdb` — `spec.bootstrap.recovery.source` names an `externalClusters` entry reading the object store, so a cluster recreated from scratch restores rather than starting empty. blocky, gotify and nextcloud declare a `Cluster` and nothing else: no `ObjectStore`, no WAL archiver plugin, no `ScheduledBackup`, and an `initdb` bootstrap — their databases have no off-cluster copy at all.

## Rotating servarr's archive path

Two `serverName`s in `servarr.cue` decide a restore and they must never be equal: `_archiveTo` is where the live cluster archives, `_recoverFrom` is where the bootstrap reads. **Every restore rotates them** — the current `_archiveTo` value moves into `_recoverFrom`, and `_archiveTo` takes a name no prefix in the bucket uses yet. The trailing counter is a token, not arithmetic.

Rotating is not cosmetic. A recovery bootstrap runs `barman-cloud-check-wal-archive` against its own archive destination first and aborts with `Expected empty archive` if anything is there, so a restore aimed at the live path never starts. And if it did start, the `ObjectStore`'s 30d retention would prune after the new cluster's first successful base backup — deleting the backup the restore had just come from.

The operator latches the failure: `Cluster is unrecoverable and needs manual intervention` survives a corrected manifest. Delete the `<cluster>-1-full-recovery` Job and the instance PVCs (`<cluster>-1`, `<cluster>-1-wal`), then let Flux recreate the `Cluster`.

Postgres images come from upstream: `cue/infrastructure/controllers/cnpg-config` syncs the `image-catalogs/` directory of `github.com/cloudnative-pg/artifacts` through its own `GitRepository`, and clusters reference `ClusterImageCatalog` `postgresql-standard-trixie` by major version rather than pinning an image tag.

# Traps

- The `ObjectStore` sets `AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` to `when_required` in `instanceSidecarConfiguration`. This is a compatibility workaround for non-AWS S3 ([plugin-barman-cloud#541](https://github.com/cloudnative-pg/plugin-barman-cloud/issues/541)); removing it breaks Storj.
- A `ScheduledBackup` can fail for months while the `Cluster` stays `Ready`: base backups and WAL archiving fail independently, and only the archive's own base-backup list shows which stopped. Abandoned generation prefixes are never pruned either, because nothing archives to them any more.
- `ReplicationSource` exposes `moverAffinity` but no toleration field, and the chart's `tolerations` reach only the operator Deployment. Whether a mover can run on a `NoSchedule` node is therefore not something the manifests can state — it matters for jellyfin, whose volume lives on the reserved [`mother`](/platform/cluster-nyx.md).
- volsync and CNPG are independent. An app with both a PVC and a database needs both restored, and neither system knows about the other's point in time.
