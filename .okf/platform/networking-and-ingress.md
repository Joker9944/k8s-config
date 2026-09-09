---
type: Infrastructure
title: Networking and ingress
description: MetalLB address allocation, Traefik entrypoints and plugins, and the three middleware chains that gate every exposed service.
tags: [traefik, metallb, ingress, middleware]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T15:00:00Z }
---

# Address allocation

MetalLB owns a single `IPAddressPool` named `internal`, `192.168.0.128/25`, advertised in L2 mode (`cue/infrastructure/controllers/metallb-config`). Traefik takes `192.168.0.128` with `externalTrafficPolicy: Local`; any other `LoadBalancer` service pins its own address with a `metallb.io/loadBalancerIPs` annotation (for example jellyfin's DLNA autodiscovery service on `192.168.0.130`). The `metallb.universe.tf` prefix that spelling supersedes is deprecated upstream and no longer used here.

# Traefik

Ingress is HTTPS-only through the `websecure` entrypoint. Every `Ingress` sets `traefik.ingress.kubernetes.io/router.tls: "true"`, names an entrypoint, names a middleware chain, and references the wildcard TLS secret from [PKI](/platform/certificates-and-pki.md).

The chart's `values.schema.json` closes the top level, so a values key a chart major has renamed away fails the HelmRelease outright rather than being ignored. That is what makes a major bump here a values migration rather than a version bump.

Two experimental plugins are loaded, both tracked by renovate against github-tags:

- `geoblock` (`github.com/PascalMinder/geoblock`) — backs the country whitelist.
- `oidc` (`github.com/lukaszraczylo/traefikoidc`) <!-- cSpell:ignore lukaszraczylo --> — puts [kanidm](/platform/identity-kanidm.md) in front of apps that have no OIDC support of their own. Session state lives in a dedicated `traefik-oidc-redis` replication cluster from the ot-helm Redis operator, which is why `traefik` `dependsOn` `redis-operator`.

# Middleware chains

`#Middlewares` installs the same set into every namespace, taking the namespace as a parameter; a bundle with no ingress switches it off. Three chains are meant to be referenced from an ingress:

| Chain                              | Composition                                                                                                                              |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `chain-basic`                      | `basic-ratelimit` (600 avg / 400 burst) + `basic-secure-headers` (HSTS 2y, nosniff, XSS filter, `X-Forwarded-Proto: https`) + `compress` |
| `chain-network-internal-whitelist` | `network-internal-whitelist` + the three basic middlewares                                                                               |
| `chain-country-whitelist`          | `country-whitelist` + the three basic middlewares                                                                                        |

`network-internal-whitelist` admits the LAN (`192.168.0.0/23`, `fe80::/10`), the tailnet (`100.0.0.0/8`, `fd7a:115c:a1e0::/48`) and the pod network, which comes from [`#PodCIDR`](/architecture/cue-layout.md).

**The cluster networks are k3s's, not kubeadm's**: pods are `10.42.0.0/16` and services `10.43.0.0/16`, against the `10.244.0.0/16` and `10.96.0.0/12` a kubeadm cluster would use. The move off Talos changed both, and the old values survived in five places — the allow-list itself plus every workload that trusts the reverse proxy or firewalls its own egress. A wrong pod CIDR here rejects any in-cluster caller of an internally-whitelisted ingress, silently and with a plain 403; Traefik's JSON access log is what names the `ClientHost` it actually saw. `country-whitelist` allows CH, DK and FR plus the tailnet, rejecting unknown countries.

The chain is selected per-service: infrastructure dashboards (Longhorn, Prometheus, Alertmanager) take the internal whitelist; public-facing apps take the country whitelist. There is no third option: `#Release` has no field for a bare middleware, so an ingress that skips the rate limit, the secure headers and compression cannot be expressed.

The `basic-*` middlewares are ported from the TrueCharts Traefik chart and kept under their original names for compatibility with other TrueCharts charts still in use.

# Naming the chain from an ingress

Middleware references are namespace-qualified (`<namespace>-<chain>@kubernetescrd`). `#IngressAnnotations` derives the prefix from the namespace it is handed and no call site writes the string, so an ingress cannot name a middleware that does not exist in its own namespace. That used to be the most common source of breakage here.

# DNS

`blocky` (`cue/apps/utility/blocky`) serves DNS over DoH upstreams with denylist filtering. Its `files/config.yml` is a **jinja template**, not a finished config: a `#ConfigMapFiles` volume mounts it at `/templates`, and a `ghcr.io/joker9944/jinja-cli` init container renders it to an `emptyDir` so `{{ environ(...) }}` can pull in the namespace and the Postgres URI at start-up. Query logs go to its own CNPG cluster; the cache goes to a standalone `redis` release from the ot-helm operator.
