---
type: Architecture
title: Repository layout
description: The top-level trees of k8s-config, and why everything Kubernetes-shaped lives under one CUE module.
tags: [gitops, layout]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-08T20:36:00Z }
---

# Trees

| Path               | Holds                                                                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cue/`             | The CUE module — every workload, the schema, and the render. See [the CUE layout](/architecture/cue-layout.md).                                        |
| `clusters/nyx/`    | The Flux bootstrap script and the Flux entry point (`flux/`). Machine configuration is not in this repo — see [the cluster](/platform/cluster-nyx.md). |
| `images/`, `pkgs/` | Nix derivations for the OCI images and helper programs this repo publishes.                                                                            |
| `.config/`         | cspell configuration.                                                                                                                                  |
| `.okf/`            | This bundle.                                                                                                                                           |

# One module, one root

Everything the cluster runs is inside `cue/`, because CUE resolves imports and
`@embed` against the module root and [`#Bundle.secretFiles`](/architecture/cue-layout.md)
holds module-relative paths. Putting the module anywhere but its own directory
would scatter `apps/`, `infrastructure/`, `schema/` and `cue.mod/` across the
repository root for no gain.

`cue/clusters/nyx/flux/` is the one place a source path and its output path
differ only by that prefix: it holds the CUE that generates
`clusters/nyx/flux/{app,infrastructure}-sync.yaml`, which are committed.

# There is no base/overlay split

`nyx` is the only cluster and nothing was ever parameterized per cluster, so the
tier collector is simultaneously the tier definition and the cluster overlay. A
second cluster would reintroduce the split as `clusters/<name>/` collectors.

Cluster membership is expressed by naming a workload in its tier collector; that
is what deploys it. The wiring is described in
[the Flux topology](/architecture/flux-topology.md).
