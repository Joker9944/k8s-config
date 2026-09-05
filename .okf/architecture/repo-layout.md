---
type: Architecture
title: Repository layout
description: The top-level trees of k8s-config and the base/overlay split that separates a deployable unit from the cluster that selects it.
tags: [gitops, layout]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T20:40:00Z }
---

# Trees

| Path               | Holds                                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `clusters/nyx/`    | The cluster's own definition: Talos machine config (`talos/`), the Flux bootstrap script, and the top-level Flux Kustomizations (`flux/`). |
| `infrastructure/`  | Platform services, grouped into the `controllers`, `plugins`, `observability`, `security` and `storage` tiers.                             |
| `apps/`            | User-facing workloads, grouped into the `cloud`, `media` and `utility` tiers.                                                              |
| `components/`      | Reusable kustomize `Component`s shared by both trees.                                                                                      |
| `images/`, `pkgs/` | Nix derivations for the OCI images and helper programs this repo publishes.                                                                |
| `.config/`         | cspell configuration and the `cspell-dicts` submodule.                                                                                     |
| `experiments/`     | Evaluations that are not deployed and not reconciled by Flux. Each carries its own README.                                                 |

# The base/overlay split

Both `apps/` and `infrastructure/` split into `base/` and `nyx/`:

- `*/base/<name>/` is a **self-contained deployable unit** — a kustomize overlay owning its namespace, HelmRelease, secrets and components. It names no cluster. Its shape is described in [the app-template pattern](/architecture/app-template-pattern.md).
- `*/nyx/<tier>/` is the **cluster overlay**: a `<tier>-sync.yaml` listing one Flux `Kustomization` per workload, each pointing at a `*/base/` path. `infrastructure/nyx/config/` additionally holds cluster-singleton resources (`certs`, `cnpg`, `longhorn`, `metallb`) that have no `base/` counterpart because there is nothing to reuse.

Cluster membership is expressed only in the overlay: deploying a workload means adding an entry to a `<tier>-sync.yaml`, never editing anything under `base/`. `nyx` is the only cluster, so the split is an enforced convention rather than an exercised abstraction — nothing in `base/` has ever been parameterized per cluster.

The wiring between the two halves is described in [the Flux topology](/architecture/flux-topology.md); the shared machinery that makes `base/` directories this terse is in [kustomize components](/architecture/kustomize-components.md).
