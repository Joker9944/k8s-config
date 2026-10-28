---
type: Reference
title: Reclaiming opencloud file revisions
description: decomposedfs keeps every overwrite forever and has no retention knob, so an autosaving client fills Garage — how to find the offenders, purge them, and what the purge tool cannot reach.
tags: [opencloud, revisions, versioning, garage, s3, decomposedfs, storage]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-27T20:15:00Z }
---

<!-- cSpell:ignore decomposedfs decomposeds bfly treesize mountid spaceid nodeid -->

# Revisions are unbounded

decomposedfs turns every upload to an existing filename into a revision:
`<nodeid>.REV.<rfc3339nano>` plus `.mpk` and `.mlock` sidecars on
[the data volume](/platform/storage.md), and a **separate blob** in Garage.
Nothing expires them, and the `decomposeds3` driver exposes no retention knob —
the only versioning switches in the binary are `OC_DISABLE_VERSIONING` (global,
turns overwrite into replace, unset here) and
`STORAGE_USERS_POSIX_ENABLE_FS_REVISIONS` (posix driver only). Retention is
designed but unbuilt upstream:
[opencloud#1419](https://github.com/opencloud-eu/opencloud/issues/1419) — open,
`p3-medium`, unmilestoned since 2025-08.

A space's treesize does **not** count revisions, so quota reads normal however
far the bucket has drifted. `garage bucket info` is the only place the growth is
visible.

# Whole-file rewrites are the failure mode

A client that rewrites a whole archive per save multiplies the archive by its
save count. Butterfly (`.bfly`, one zip per notebook, autosave per scribble) is
the case here: a 28MB notebook reached 4012 revisions and 56GiB, four notebooks
held 97.8GiB against ~23GiB of live data, growing ~2GiB per day of editing.

# Finding the offenders

Revisions exist only on disk, so group them by node and read the names back out
of the metadata:

```sh
find /var/lib/opencloud/storage/users/spaces -name '*.REV.*.mpk' \
  | sed 's/\.REV\..*//' | sort | uniq -c | sort -rn
```

A node's name and current size come from its sibling `<nodeid>.mpk`: `strings`
it for `user.oc.name` and `user.oc.blobsize`. It is messagepack, so a one-byte
length prefix precedes each value and bleeds into `strings` output. Summing
`user.oc.blobsize` across a node's `.REV.*.mpk` gives the reclaimable bytes.
Butterfly also writes a base64-named sidecar per notebook — `cmVtb3RlOi9...`
decodes to `remote:/<name>.bfly` — which versions just as hard at ~1KB a
revision.

# Purging

`opencloud revisions purge` is the tool. It is undocumented in the chart and
sits at the top level, not under `opencloud decomposedfs`:

```sh
opencloud revisions purge -p /var/lib/opencloud/storage/users -b decomposeds3 \
  -r '<mountid>$<spaceid>!<nodeid>' --dry-run=false
```

- `-b decomposeds3` is required; the default `decomposed` would delete the
  metadata and orphan the Garage blobs.
- `--dry-run` defaults to **true**.
- `-r` takes a space or a single file, and purges everything when omitted. It
  keeps the current version and deletes every revision — there is no keep-last-N,
  so selective retention means enumerating node ids.
- `--glob-mechanism workers` is far faster but contends with
  [bleve's allocation burst](/workflows/opencloud-memory.md) for the memory
  limit. The default single-worker `glob` cleared 11947 revisions in five
  minutes.
- The S3 credentials are read from `STORAGE_USERS_DECOMPOSEDS3_*` in the
  container's environment, so this only works `kubectl exec`'d into the running
  pod. `decomposedfs check-treesize --repair` wants opencloud stopped, but is not
  needed after a purge, because treesize never counted the revisions.

**Trap:** the tool only matches revisions whose timestamp carries fractional
seconds. Second-precision ones — written when the client supplies an integer
mtime, as sync clients do — are invisible to it at every scope and cannot be
reclaimed with it at all. 351 of 12864 revisions here.

# Garage frees the space a day later

Deleting blobs enqueues resync work rather than releasing blocks. Straight after
a 98GiB purge `garage status` still showed `DataAvail` unchanged and the resync
queue at ~90k per node; reclaim follows Garage's block GC delay, 24h by default.
Plan a purge before the disks are tight enough that a day matters.
