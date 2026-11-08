---
type: Decision
title: Jellyseerr is now seerr, under its old names
description: The jellyseerr package runs ghcr.io/seerr-team/seerr but keeps its namespace, PVC, restic repository and public host, because the sqlite migration is forward-only and a rename would move the data at the same time.
tags: [jellyseerr, seerr, migration, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-08T12:00:00Z }
stale_after: 2027-05-08
---

# Decision

Jellyseerr and Overseerr merged upstream into **seerr** in February 2026;
`fallenbagel/jellyseerr` was transferred and renamed to `seerr-team/seerr`. The
package follows the image to `ghcr.io/seerr-team/seerr` and nothing else: the
namespace, the release, the `jellyseerr-config` PVC, the
`jellyseerr-restic-config` repository and `jellyseerr.vonarx.online` all keep
their old spelling. A pointer comment at the top of the package says so, because
the mismatch otherwise reads as a bug.

# Why

The upgrade runs TypeORM migrations and a settings migrator over the existing
`/app/config` on first boot. It is forward-only — there is no down path, and
rolling back the tag leaves a v3 database under a v2 binary. The only rollback
is the restic snapshot, so the upgrade's precondition is a fresh
[ReplicationSource run](/platform/backup-and-restore.md).

A rename would have moved namespace, PVC and restic repository in the same
change, so a failed migration would have had to be debugged through a half-moved
namespace. The names are cosmetic; the database is not.

# The init advice does not apply here

The old image ran `tini` as PID 1; the new one runs `docker-entrypoint.sh` →
`npm start`, and upstream's migration guide says to answer that with Compose's
`init: true`. There is no Kubernetes equivalent, and **none is needed** —
measured against v3.0.1 in the pod's own shape, `npm` installs its own SIGTERM
handler and forwards to `node` at PID 2, which exits in well under a second.
Overriding `command` to `node dist/index.js` makes this strictly worse: node
becomes PID 1, where the kernel supplies no default SIGTERM disposition and the
app installs no handler, so the container hangs for the full grace period and
dies of SIGKILL. The image's own command is the one that shuts down cleanly.
seerr forks nothing, so nothing needs reaping either.

npm exits 1 on the forwarded signal, so a deliberately terminated container's
last state reads `Error`.

Under `runAsUser: 568` there is no passwd entry, so `HOME` falls back to `/` —
that is why `/.cache` exists. v3.0.1 boots clean with only `/.cache` and `/tmp`
writable; it never touches `/.yarn`, which is gone, and it needs no `/.npm`
(npm's error log is the only casualty, and the container log carries the same
error). The image declares `USER node:node` (1000); the pod keeps 568 with a
matching `fsGroup`, because the config volume's files are owned by 568.

# What it costs

Every identifier names a product that no longer exists, and the rename only gets
harder as the restic repository's history lengthens. Renovate is unaffected —
the generic `repository:`/`tag:` manager in `renovate.json5` needs no annotation.
A later rename is a restore: a re-encrypted secret pointing at the same bucket
path, plus a one-off `dest-config` flip in `#VolsyncRestic`.
