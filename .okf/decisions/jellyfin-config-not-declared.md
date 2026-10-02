---
type: Decision
title: Jellyfin's config is not declared
description: Jellyfin's settings stay in its config volume instead of being extracted into files/ and overlaid back, because the app rewrites the same files it reads.
tags: [jellyfin, config, volsync, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-02T10:20:08Z }
stale_after: 2027-04-02
---

# Decision

Jellyfin's configuration stays in its `config` volume. The repo declares the
deployment — the digest-pinned image, the GPU runtime class, the mounts, the
ingress, the volsync pair — and the app owns its settings.

Not taken: extraction into `files/`, and a config overlay layering those files
back over the volume.

# Why

Jellyfin rewrites the same files it reads, and several plugin configs hold
credentials inline, so there is no input the app merely consumes. An overlay
would duplicate state [volsync already protects](/platform/backup-and-restore.md)
and would revert dashboard edits on restart.

# What it costs

A settings change leaves no diff and nothing to review. Reproducibility is
restore-shaped rather than reconcile-shaped: a rebuild depends on the volsync
`dest-config` restore, not on a Flux reconcile.

[Jellyfin's config](/workflows/jellyfin-config.md) covers where the settings live
and how to reach them.
