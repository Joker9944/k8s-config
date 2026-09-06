# Architecture

How the repository is organized and how a directory of YAML becomes a reconciled cluster.

- [Repository layout](repo-layout.md) - the top-level trees and the base/overlay split.
- [Flux topology](flux-topology.md) - the three-level Kustomization graph and its ordering constraints.
- [Kustomize components](kustomize-components.md) - the shared `components/` tree and the PLACEHOLDER conventions.
- [App-template pattern](app-template-pattern.md) - the shape every workload directory takes.
- [CUE layout](cue-layout.md) - the target CUE tree: a package per workload, a collector per tier.
- [Known configuration drift](config-drift.md) - the manifests that diverge from the fleet's own conventions.
