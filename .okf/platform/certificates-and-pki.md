---
type: Infrastructure
title: Certificates and PKI
description: The two issuance paths — public ACME wildcard and a private root/intermediate CA — and the two unrelated mechanisms that distribute them across namespaces.
tags: [cert-manager, tls, pki, trust-manager]
resource: cue/infrastructure/controllers/certs-config
status: stable
generated: { by: claude-code/fable-5, at: 2026-10-25T00:00:00Z }
---

# Public path

`cloudflare-production` is the one ACME `ClusterIssuer`, solving DNS-01 against Cloudflare with the API token in `cloudflare-secret.sops.yaml`. They issue a single Certificate, `wildcard-vonarx-online` in the `cert-manager` namespace, covering `vonarx.online`, `*.vonarx.online`, `*.s3.vonarx.online` and `*.web.vonarx.online`.

Every public ingress in the repo references `secretName: wildcard-vonarx-online-cert` — the one wildcard is the whole public TLS story.

**It is the slowest thing in a cold bootstrap, by construction.** `vonarx.online` and `*.vonarx.online` are separate ACME challenges sharing one TXT name, `_acme-challenge.vonarx.online`, so cert-manager validates them in sequence: the wildcard first, then its record is torn down and the apex's published, which only then starts its own propagation clock. The other names finish long before it, so `Waiting for DNS-01 challenge propagation` on the last challenge is the normal state rather than a fault — check `dig TXT _acme-challenge.vonarx.online` against the pending challenge's `spec.key` before touching anything. Because `certs-config` waits on this Certificate and `traefik` needs it, everything behind Traefik in the [capability graph](/architecture/capability-graph.md) waits on that last challenge — which is most of the fleet. Its Kustomization `timeout` is 40m for the same reason, the longest in the fleet.

# Private path

A three-link chain for in-cluster TLS:

```
Issuer trust-manager  →  Certificate nyx-root-ca (isCA, "Nyx Root R1", 810d)
                      →  Certificate nyx-intermediate-ca (isCA, "Nyx Intermediate R1", 270d)
                      →  ClusterIssuer nyx-intermediate-ca
```

`nyx-intermediate-ca` is what [`#NamespaceCert`](/architecture/cue-layout.md) uses to mint a `*.<namespace>.svc.cluster.local` wildcard for workloads that need real TLS on the pod-to-pod hop (kanidm is the only current consumer).

The `trust-manager` `Issuer` at the root of that chain **is not defined in this repository** — it is the self-signed issuer the trust-manager chart creates in its own namespace, reused here as the cluster's signing root.

Both CA Certificates pin `privateKey.rotationPolicy: Never`. cert-manager ≥ 1.18 defaults to `Always`, which on renewal would give the CA a new key while the Bundles drop its old cert immediately — orphaning every leaf signed before the renewal until that leaf's own renewal, up to 60 days later. Key reuse keeps old leaves chaining against the renewed CA cert. Leaves keep the `Always` default; their rotation has no dependents.

# Distribution

Two mechanisms, chosen by what is being copied:

| Mechanism                  | Copies                                        | Opt-in                                                                                                                                         |
| -------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **reflector**              | whole Secrets, including private keys         | annotations on the source Secret / `secretTemplate` (`reflection-allowed`, `reflection-auto-enabled`, optionally `reflection-auto-namespaces`) |
| **trust-manager `Bundle`** | CA certificates only, as a public trust store | a label on the _destination_ namespace                                                                                                         |

The two Bundles are `nyx-ca-cert-bundle` (intermediate + root, for namespaces labelled `vonarx.online/distribute-nyx-ca-cert-bundle: "true"`) and `public-nyx-ca-cert-bundle` (the same plus `useDefaultCAs`, label `vonarx.online/distribute-public-nyx-ca-cert-bundle: "true"`). Both are listed in the chart's `secretTargets.authorizedSecrets`, without which trust-manager refuses to write them.

Delivery to a namespace is not delivery to a process: a `subPath` mount copies the Secret once at pod start and never again, and kanidmd re-reads its TLS files only on SIGHUP. kanidm therefore carries a `secret.reloader.stakater.com/reload` annotation naming its cert secret, and the `stakater` bundle's reloader rolls the statefulset when it changes — a renewal costs a restart-length SSO blip roughly every 60 days.

# Ordering

`certs-config` sets `wait: true`, so nothing that depends on it proceeds until its whole chain is genuinely issued — both CA Certificates, their Issuer and ClusterIssuer, the ACME ClusterIssuer and the wildcard. `traefik` depends on it for exactly this reason.

The two trust `Bundle`s are the deliberate exception: a namespace can still start before its CA bundle lands. Gating them would need a `healthCheckExprs` entry, because a Bundle's status carries only `Synced`, and nothing needs one — the CA arrives as a Secret that reflector copies, so a pod missing it waits in `ContainerCreating` while kubelet retries rather than failing an apply.
