---
type: Infrastructure
title: The nyx cluster
description: Node inventory, the label and taint scheme workloads schedule against, and what the cluster gets from nix-config rather than this repo.
tags: [cluster, nodes, scheduling]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-08T21:04:00Z }
---

# Nodes

Four nodes, three of them control planes that also run workloads (hence "hybrid"). All are on the tailnet as `<hostname>.<tailnet>`, with a shared VIP for the API server.

| Host           | Role          | Labels                                               |
| -------------- | ------------- | ---------------------------------------------------- |
| `nyx-hybrid-1` | control plane | cpu 12 / low, mem 31929 / high                       |
| `nyx-hybrid-2` | control plane | cpu 6 / high, mem 31929 / high                       |
| `nyx-hybrid-3` | control plane | cpu 6 / high, mem 31929 / high                       |
| `nyx-worker-1` | worker        | `nfs-host`, `s3-host`, cpu 4 / low, mem 15972 / high |

`nyx-worker-1` is the only GPU node.

# Labels and taints

Node labels live in the `vonarx.online/` namespace and are consumed as scheduling hints rather than hard constraints: `cpu-capacity`, `cpu-performance`, `memory-capacity`, `memory-performance`, plus the boolean `nfs-host` and `s3-host`. Workloads that read large volumes off the NAS declare a `preferredDuringSchedulingIgnoredDuringExecution` affinity on `vonarx.online/nfs-host`.

`nyx-worker-1` additionally carries the taint `vonarx.online/weak-node=true:PreferNoSchedule`, applied once by `clusters/nyx/bootstrap.sh` and **not** reconciled by Flux. GPU workloads pair the `nfs-host` affinity with a matching `nvidia.com/gpu` toleration.

# Machine configuration lives in nix-config

The nodes run NixOS, configured in [`Joker9944/nix-config`](https://github.com/Joker9944/nix-config). Nothing here renders, patches or applies machine configuration — this repo starts at the Kubernetes API, and `clusters/nyx/` holds only the Flux entry point and the bootstrap script.

The node labels above come from there, as do the API-server VIP and the tailnet routing: every node advertises the VIP and the [MetalLB range](/platform/networking-and-ingress.md) as tailnet routes, which is what makes both reachable off-LAN. None of it is visible in this repo, so none of it shows up in a diff when it changes.
