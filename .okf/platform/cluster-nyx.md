---
type: Infrastructure
title: The nyx cluster
description: Node inventory, the label and taint scheme workloads schedule against, and what the cluster gets from nix-config rather than this repo.
tags: [cluster, nodes, scheduling]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-08T21:50:00Z }
---

# Nodes

Four k3s nodes. Three are control planes that also run workloads; `mother` is the only worker. All are on the tailnet as `<hostname>.<tailnet>`, with a kube-vip VIP for the API server.

| Host     | Role          | CPU | Memory | Labels     |
| -------- | ------------- | --- | ------ | ---------- |
| `tars`   | control plane | 12  | 32G    | —          |
| `kipp`   | control plane | 12  | 32G    | —          |
| `case`   | control plane | 6   | 32G    | —          |
| `mother` | worker        | 8   | 64G    | `nfs-host` |

`mother` holds the ZFS pool, exports it over NFS at `192.168.0.24`, and is the only GPU node.

# Labels and taints

Node labels live in the `vonarx.online/` namespace. Only `nfs-host` is consumed by anything in this repo — jellyfin's preferred affinity.

`mother` carries `vonarx.online/reserved=storage:NoSchedule`, keeping its capacity for ZFS and NFS. [`#Reserved`](/architecture/cue-layout.md) supplies both answers to it: infrastructure that has to cover every node tolerates the key with `Exists`, and a workload deliberately placed there matches `value: storage`, so `grep` finds every such placement. Today that is jellyfin alone, which pairs it with an `nvidia.com/gpu` toleration for the GPU.

The taint comes from nix-config and is **not** reconciled by Flux.

# Machine configuration lives in nix-config

The nodes run k3s on NixOS, configured in [`Joker9944/nix-config`](https://github.com/Joker9944/nix-config). Nothing here renders, patches or applies machine configuration — this repo starts at the Kubernetes API, and `clusters/nyx/` holds only the Flux entry point and the bootstrap script.

The node labels above come from there, as do the API-server VIP and the tailnet routing: every node advertises the VIP and the [MetalLB range](/platform/networking-and-ingress.md) as tailnet routes, which is what makes both reachable off-LAN. None of it is visible in this repo, so none of it shows up in a diff when it changes.
