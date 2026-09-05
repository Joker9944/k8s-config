---
type: Infrastructure
title: The nyx Talos cluster
description: Node inventory, labelling scheme, and how machine configuration is rendered from talconfig.yaml by talhelper.
tags: [talos, cluster, nodes]
resource: clusters/nyx/talos/talconfig.yaml
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# Nodes

Four nodes, three of them control planes that also run workloads (hence "hybrid"). All reachable over Tailscale as `<hostname>.${TAILNET_NAME}`, with a shared VIP for the API server.

| Host           | Role          | Disk           | Notable extensions                                                                          | Labels                                               |
| -------------- | ------------- | -------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `nyx-hybrid-1` | control plane | `/dev/nvme0n1` | —                                                                                           | cpu 12 / low, mem 31929 / high                       |
| `nyx-hybrid-2` | control plane | `/dev/nvme0n1` | `realtek-firmware`                                                                          | cpu 6 / high, mem 31929 / high                       |
| `nyx-hybrid-3` | control plane | `/dev/nvme0n1` | `realtek-firmware`                                                                          | cpu 6 / high, mem 31929 / high                       |
| `nyx-worker-1` | worker        | `/dev/vda`     | `qemu-guest-agent`, `nonfree-kmod-nvidia-production`, `nvidia-container-toolkit-production` | `nfs-host`, `s3-host`, cpu 4 / low, mem 15972 / high |

Every node carries `iscsi-tools` and `util-linux-tools` (required by Longhorn) and `tailscale`.

# Labels and taints

Node labels live in the `vonarx.online/` namespace and are consumed as scheduling hints rather than hard constraints: `cpu-capacity`, `cpu-performance`, `memory-capacity`, `memory-performance`, plus the boolean `nfs-host` and `s3-host`. Workloads that read large volumes off the NAS declare a `preferredDuringSchedulingIgnoredDuringExecution` affinity on `vonarx.online/nfs-host`.

`nyx-worker-1` additionally carries the taint `vonarx.online/weak-node=true:PreferNoSchedule`, applied once by `clusters/nyx/bootstrap.sh` and **not** reconciled by Flux. It is the only GPU node, so GPU workloads pair the affinity with a matching `nvidia.com/gpu` toleration.

# Rendering

`talhelper` (pinned as a flake input, `v3.1.3`) renders `talconfig.yaml` plus `patches/` into machine configs.

- `talenv.yaml` (SOPS, whole file) supplies the `${…}` substitutions: `VIP`, `TAILNET_NAME`, `GATEWAY_IP`, the per-node IPs, `ADDRESS_SPACE`, `LOAD_BALANCER_SPACE`, the nameservers and NTP.
- `talsecret.sops.yaml` holds the cluster PKI.
- Output lands in `clusters/nyx/talos/clusterconfig/`, which is gitignored. The [dev shell](/workflows/dev-environment.md) exports `TALOSCONFIG` to point at it.

Patches under `clusters/nyx/talos/patches/` are referenced with `@patches/<name>.yaml` and split by concern: `control-plane-hybrid`, `control-plane-tailscale`, `cpu-manager`, `kube-proxy-metrics`, `longhorn`, `ntp`, `nvidia`, `tailscale`. Node-specific patches attach to the node; cluster-wide ones attach to `controlPlane:` / `worker:`.

Tailscale runs as a Talos `extensionServices` entry on every node advertising `TS_ROUTES=${VIP}/32,${LOAD_BALANCER_SPACE}`, which is how the [MetalLB range](/platform/networking-and-ingress.md) becomes reachable off-LAN.

`talosVersion` and `kubernetesVersion` carry `# renovate:` comments and are gated behind dependency-dashboard approval — they never automerge. See [dependency updates](/workflows/images-and-ci.md).
