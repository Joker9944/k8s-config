---
type: Infrastructure
title: Networking and ingress
description: MetalLB address allocation, Traefik entrypoints and plugins, and the three middleware chains that gate every exposed service.
tags: [traefik, metallb, ingress, middleware]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# Address allocation

MetalLB owns a single `IPAddressPool` named `internal`, `192.168.0.128/25`, advertised in L2 mode (`infrastructure/nyx/config/metallb`). Traefik takes `192.168.0.128` with `externalTrafficPolicy: Local`; any other `LoadBalancer` service pins its own address with a `metallb.universe.tf/loadBalancerIPs` annotation (for example jellyfin's DLNA autodiscovery service on `192.168.0.130`).

# Traefik

Ingress is HTTPS-only through the `websecure` entrypoint. Every `Ingress` sets `traefik.ingress.kubernetes.io/router.tls: "true"`, names an entrypoint, names a middleware chain, and references the wildcard TLS secret from [PKI](/platform/certificates-and-pki.md).

Two experimental plugins are loaded, both tracked by renovate against github-tags:

- `geoblock` (`github.com/PascalMinder/geoblock`) — backs the country whitelist.
- `oidc` (`github.com/lukaszraczylo/traefikoidc`) <!-- cSpell:ignore lukaszraczylo --> — puts [kanidm](/platform/identity-kanidm.md) in front of apps that have no OIDC support of their own. Session state lives in a dedicated `traefik-oidc-redis` replication cluster from the ot-helm Redis operator, which is why `traefik` `dependsOn` `redis-operator`.

# Middleware chains

`components/common-middlewares` installs the same set into every namespace that pulls it in. Three chains are meant to be referenced from an ingress:

| Chain                              | Composition                                                                                                                              |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `chain-basic`                      | `basic-ratelimit` (600 avg / 400 burst) + `basic-secure-headers` (HSTS 2y, nosniff, XSS filter, `X-Forwarded-Proto: https`) + `compress` |
| `chain-network-internal-whitelist` | `network-internal-whitelist` + the three basic middlewares                                                                               |
| `chain-country-whitelist`          | `country-whitelist` + the three basic middlewares                                                                                        |

`network-internal-whitelist` admits the LAN (`192.168.1.0/23`, `fe80::/10`), the tailnet (`100.0.0.0/8`, `fd7a:115c:a1e0::/48`) and the pod network (`10.244.0.0/16`). `country-whitelist` allows CH, DK and FR plus the tailnet, rejecting unknown countries.

The chain is selected per-service: infrastructure dashboards (Longhorn, Prometheus, Alertmanager) take the internal whitelist; public-facing apps take the country whitelist.

The `basic-*` middlewares are ported from the TrueCharts Traefik chart and kept under their original names for compatibility with other TrueCharts charts still in use — the comment in `manifests/middleware.yaml` is the only record of that constraint.

# Naming the chain from an ingress

Middleware references are namespace-qualified (`<namespace>-<chain>@kubernetescrd`). How that namespace gets into the annotation differs between trees and is the most common source of breakage — see the traps in [kustomize components](/architecture/kustomize-components.md).

# DNS

`blocky` (`apps/base/blocky`, `utility` tier) serves DNS over DoH upstreams with denylist filtering. Its `files/config.yml` is a **jinja template**, not a finished config: a `configMap` volume mounts it at `/templates`, and a `ghcr.io/joker9944/jinja-cli` init container renders it to an `emptyDir` so `{{ environ(...) }}` can pull in the namespace and the Postgres URI at start-up. Query logs go to its own CNPG cluster; the cache goes to a standalone `redis` release from the ot-helm operator.
