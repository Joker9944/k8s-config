---
type: Infrastructure
title: The nyx cluster
description: Node inventory, the label and taint scheme workloads schedule against, and what the cluster gets from nix-config rather than this repo.
tags: [cluster, nodes, scheduling]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T19:00:00Z }
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

The GPU reaches pods through the **`nvidia-cdi` containerd handler**. `nvidia-container-toolkit` writes a CDI spec to `/run/cdi` declaring `nvidia.com/gpu=0` and `=all` — index names only, no UUIDs, which is what forces the device plugin's `deviceIDStrategy: index`. k3s registers both an `nvidia` and an `nvidia-cdi` handler once nix-config puts `nvidia-container-runtime` on its PATH. Only the second is usable: the plain one runs the runtime in auto mode and reaches for a legacy libnvidia-container driver tree no NixOS host has, failing the container with `exit status 2`.

k3s's `runtimes` Addon ships RuntimeClasses for `nvidia`, `crun` and the wasm handlers, but none for `nvidia-cdi` — that one is created by this repo, alongside the device plugin. Two traps sit next to it. **Pod `cdi.k8s.io/*` annotations do nothing**: containerd 2.0 dropped that injection path for the CRI `CDIDevices` field, so an annotation is ignored rather than rejected, and the workload starts with no GPU. And **nothing taints the GPU node** — an `nvidia.com/gpu` toleration is dead weight; `nvidia.com/gpu: 1` in a container's limits is what places a pod on `mother`.

`generic-device-plugin` advertises `/dev/net/tun` on every node as **`devic.es/tun`** — upstream renamed the domain from `squat.ai`, and its `--domain` flag is left at the default. A request for the old name is not a scheduling shortage; it is a resource no node has.

# Labels and taints

Node labels live in the `vonarx.online/` namespace. Only `nfs-host` is consumed by anything in this repo — jellyfin's required affinity, which pins it here for a [hostPath on the pool](/platform/storage.md) rather than for NFS locality.

`mother` carries `vonarx.online/reserved=storage:NoSchedule`, keeping its capacity for ZFS and NFS. [`#Reserved`](/architecture/cue-layout.md) supplies both answers to it: infrastructure that has to cover every node tolerates the key with `Exists`, and a workload deliberately placed there matches `value: storage`, so `grep` finds every such placement. Today that is jellyfin alone.

The taint comes from nix-config and is **not** reconciled by Flux.

# Pod Security

A workload that needs a hostPath or a root container needs `pod-security.kubernetes.io/enforce: privileged` on its namespace, set through `#Bundle`'s `namespaceLabels`.

Talos applied its admission configuration from its own defaults rather than from anything checked in here, and the retired `clusters/nyx/talos/` tree never mentioned it — so grepping this repo for what these labels answer to finds nothing. Treat them as deliberate; do not prune them as cargo cult.

# Machine configuration lives in nix-config

The nodes run k3s on NixOS, configured in [`Joker9944/nix-config`](https://github.com/Joker9944/nix-config). Nothing here renders, patches or applies machine configuration — this repo starts at the Kubernetes API, and `clusters/nyx/` holds only the Flux entry point and the bootstrap script.

The node labels above come from there, as do the API-server VIP and the tailnet routing: every node advertises the VIP and the [MetalLB range](/platform/networking-and-ingress.md) as tailnet routes, which is what makes both reachable off-LAN. None of it is visible in this repo, so none of it shows up in a diff when it changes.
