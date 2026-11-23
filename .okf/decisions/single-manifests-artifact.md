---
type: Decision
title: One manifests artifact
description: Every bundle ships in the one nyx-manifests OCI artifact; the per-tier artifacts are gone, and rendering stays in CI.
tags: [gitops, flux, oci, cue, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-23T18:00:00Z }
---

# Decision

[The CUE render](/architecture/cue-layout.md) produces one artifact, `nyx-manifests`, holding every bundle, reconciled by one level-2 Kustomization ([Flux topology](/architecture/flux-topology.md)). `infrastructure/` and `apps/` remain as folders only.

# Why the tiers went

Tiers came from the kustomize era, where level 2 was ordered tier by tier. Once ordering moved to the per-bundle [capability graph](/architecture/capability-graph.md), a tier decided only which artifact a bundle shipped in, and nothing constrained the choice — membership drifted to "least wrong" (headlamp in `security`).

Their remaining argument was blast radius: one evaluation error stalling only its own tier. That is weaker than it looks. A failed render publishes nothing, so running workloads are untouched either way; and `checks.cueVet` gates every pull request.

# What it costs

- Any edit that changes a manifest republishes the whole artifact, and all level-3 Kustomizations reconcile against the new revision. They re-apply nothing that did not change; it is churn, not risk.
- An evaluation error anywhere stalls updates everywhere until fixed — on direct pushes to `main`, which no pull-request check sees.
- Every edit rebuilds the one derivation. The evaluation takes well under a second.

If the churn becomes a problem, Flux's `ArtifactGenerator` (the opt-in source-watcher controller) can split the artifact per bundle in-cluster, with nothing else changing.

# Rejected

| Option                                   | Why not                                                                                                                                                                                                  |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One artifact per bundle                  | 32 OCIRepositories, signature checks and GHCR packages, a dynamic CI matrix, and the level-3 sync layer needs a home of its own — all to avoid churn.                                                    |
| flux-kcl-controller and a rewrite in KCL | `KCLRun` has no SOPS decryption and no `deletionPolicy`; the controller is `v1alpha1` with effectively one maintainer, and v0.12.0 shipped a chart that crash-looped. It would deploy the whole cluster. |
| A CUE controller of our own              | Reading git directly trades the cosign-on-`main` trust anchor for commit-signature verification of every commit; keeping OCI keeps CI in the deploy path and removes the reason to write it.             |
