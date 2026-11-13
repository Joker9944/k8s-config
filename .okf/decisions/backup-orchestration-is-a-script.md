---
type: Decision
title: Backup orchestration is a script
description: Why opencloud's orchestrated backup is a script rather than a Kanister Blueprint, and when to revisit.
tags: [backup, volsync, rclone, kanister, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-24T12:00:00Z }
---

# Decision

[opencloud's orchestrated backup](/platform/backup-and-restore.md) is a script, not a Kanister Blueprint.

# Why not an off-the-shelf tool

No tool captures a PVC and an object-storage bucket inside one quiesce window. Velero and K8up back up PVCs with in-pod hooks but cannot scale a workload down; volsync's copy trigger pauses its own clone but quiesces nothing; nothing mirrors a bucket, so the rclone step is ours regardless.

Kanister comes closest: a `Blueprint` declares the backup and restore actions as phases (`ScaleWorkload`, `KubeTask`, `BackupData`, a deferred scale-up), each `ActionSet` is an observable run, and backup outputs feed restore. For one workload it buys structure, not fewer parts:

- No scheduler — a CronJob still creates the `ActionSet`.
- The bucket phase is a `KubeTask` running the same rclone command, in the same image.
- `BackupData` would give opencloud a second backup tool and repository format beside volsync; a `KubeTask` driving volsync instead is the script cut into YAML.
- One more operator, and Go templates in YAML generated from CUE.

# Revisit when

A second workload needs a coordinated multi-part backup — a dump plus a PVC, or anything that must be stopped first. One Blueprint pattern then beats a second copy of the script.
