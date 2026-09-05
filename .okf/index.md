---
okf_version: "0.2"
---

# k8s-config

GitOps configuration for **nyx** — a four-node Talos cluster reconciled by Flux, serving `vonarx.online`. Start with [repository layout](architecture/repo-layout.md); it names every top-level tree and the base/overlay split everything else assumes.

# Architecture

- [Repository layout](architecture/repo-layout.md) - the top-level trees and the base/overlay split.
- [Flux topology](architecture/flux-topology.md) - the three-level Kustomization graph and its ordering constraints.
- [Kustomize components](architecture/kustomize-components.md) - the shared `components/` tree and the PLACEHOLDER conventions.
- [App-template pattern](architecture/app-template-pattern.md) - the shape every workload directory takes.

# Platform

- [The nyx Talos cluster](platform/talos-nyx.md) - node inventory, labelling, and talhelper rendering.
- [Networking and ingress](platform/networking-and-ingress.md) - MetalLB, Traefik, and the three middleware chains.
- [Certificates and PKI](platform/certificates-and-pki.md) - the public ACME wildcard, the private CA chain, and how both are distributed.
- [Identity — kanidm](platform/identity-kanidm.md) - the OIDC provider, and why client registration is manual.
- [Storage](platform/storage.md) - the three Longhorn classes, NFS media, and Garage object storage.
- [Backup and restore](platform/backup-and-restore.md) - volsync/restic for PVCs, CNPG/barman-cloud for Postgres.
- [Observability](platform/observability.md) - Prometheus, Loki, Alloy, and the Gotify alerting path.

# Workflows

- [Adding an app](workflows/adding-an-app.md) - the end-to-end sequence, including what Flux cannot do for you.
- [Development environment](workflows/dev-environment.md) - what the Nix flake provides.
- [Secrets and SOPS](workflows/secrets-sops.md) - how a filename decides its encryption rule.
- [Formatting and cspell](workflows/formatting-and-cspell.md) - the pre-commit suite and the dictionary submodule.
- [Images, CI and dependency updates](workflows/images-and-ci.md) - Nix-built OCI images, signing, and renovate.
