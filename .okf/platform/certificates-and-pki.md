---
type: Infrastructure
title: Certificates and PKI
description: The two issuance paths — public ACME wildcard and a private root/intermediate CA — and the two unrelated mechanisms that distribute them across namespaces.
tags: [cert-manager, tls, pki, trust-manager]
resource: infrastructure/nyx/config/certs
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# Public path

`cloudflare-production` (and an unused `cloudflare-staging`) are ACME `ClusterIssuer`s solving DNS-01 against Cloudflare, with the API token in `cloudflare-secret.sops.yaml`. They issue a single Certificate, `wildcard-vonarx-online` in the `cert-manager` namespace, covering `vonarx.online`, `*.vonarx.online`, `*.s3.vonarx.online` and `*.web.vonarx.online`.

Every public ingress in the repo references `secretName: wildcard-vonarx-online-cert` — the one wildcard is the whole public TLS story.

# Private path

A three-link chain for in-cluster TLS:

```
Issuer trust-manager  →  Certificate nyx-root-ca (isCA, "Nyx Root R1", 810d)
                      →  Certificate nyx-intermediate-ca (isCA, "Nyx Intermediate R1", 270d)
                      →  ClusterIssuer nyx-intermediate-ca
```

`nyx-intermediate-ca` is what the [`namespace-cert*` components](/architecture/kustomize-components.md) use to mint a `*.<namespace>.svc.cluster.local` wildcard for workloads that need real TLS on the pod-to-pod hop (kanidm is the only current consumer).

The `trust-manager` `Issuer` at the root of that chain **is not defined in this repository** — it is the self-signed issuer the trust-manager chart creates in its own namespace, reused here as the cluster's signing root.

# Distribution

Two mechanisms, chosen by what is being copied:

| Mechanism                  | Copies                                        | Opt-in                                                                                                                                         |
| -------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **reflector**              | whole Secrets, including private keys         | annotations on the source Secret / `secretTemplate` (`reflection-allowed`, `reflection-auto-enabled`, optionally `reflection-auto-namespaces`) |
| **trust-manager `Bundle`** | CA certificates only, as a public trust store | a label on the _destination_ namespace                                                                                                         |

The two Bundles are `nyx-ca-cert-bundle` (intermediate + root, for namespaces labelled `vonarx.online/distribute-nyx-ca-cert-bundle: "true"`) and `public-nyx-ca-cert-bundle` (the same plus `useDefaultCAs`, label `vonarx.online/distribute-public-nyx-ca-cert-bundle: "true"`). Both are listed in the chart's `secretTargets.authorizedSecrets`, without which trust-manager refuses to write them.

# Ordering

`certs-config` declares Flux `healthChecks` on `wildcard-vonarx-online` and `nyx-intermediate-ca`, so nothing that depends on it proceeds until both are genuinely issued. `traefik` depends on `certs-config` for exactly this reason. A `TODO healthcheck for bundle` records that Bundle readiness is not yet gated — a namespace can therefore start before its CA bundle lands.
