# Architecture

How the repository is organized and how a CUE package becomes a reconciled cluster.

- [Repository layout](repo-layout.md) - the top-level trees and the one CUE module.
- [Flux topology](flux-topology.md) - the three-level Kustomization graph, its artifacts and its ordering constraints.
- [App-template pattern](app-template-pattern.md) - the shape every workload package takes.
- [CUE layout](cue-layout.md) - the CUE tree: a package per workload, a collector per tier.
