---
type: Decision
title: The Nix binary cache is not in the cluster
description: The private Nix cache is harmonia on mother, managed in nix-config; attic was tried here and removed because its S3 backend hands clients presigned URLs on Garage's in-cluster endpoint.
tags: [nix, attic, harmonia, garage, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-16T21:00:00Z }
---

# Decision

The private binary cache nix-config's CI pushes to and every host reads from is harmonia serving mother's `/nix/store`, declared in nix-config. Nothing in this repo serves it.

# Why

attic was deployed here on Garage and removed. For a NAR stored as a single chunk — anything under about 256 KiB — `get_nar` answers with a `307` to a presigned URL built from the configured S3 endpoint (`api/binary_cache.rs`, `storage/s3.rs`, not configurable), and `garage.garage.svc.cluster.local` resolves nowhere a client is. Fixing that meant either attic's local storage, giving up Garage and putting the chunks on a single-replica volume, or pointing the endpoint at the public `s3.vonarx.online` and routing every transfer through the edge. Neither beat a Nix store: harmonia uses Nix's own closure-aware GC and `nix store optimise`, idles at ~8 MiB, and attic is unversioned, experimental software.

harmonia has no authentication of its own, so access control is the tailnet policy for reads and SSH with signed paths for pushes.
