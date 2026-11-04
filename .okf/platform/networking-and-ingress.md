---
type: Infrastructure
title: Networking and ingress
description: The WireGuard edge the cluster is reached through, Traefik entrypoints and plugins, the two middleware chains that gate every public service, the tailnet path that carries everything else, and how a VPN sidecar rewrites pod DNS.
tags: [traefik, wireguard, ingress, middleware, tailscale]
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-04T00:00:00Z }
---

# The edge

**The cluster is behind CGNAT and cannot listen.** Public traffic arrives at a VPS, `wopr` (`62.83.98.27`), which runs nginx, terminates no TLS, and shovels raw TCP into a hub-spoke WireGuard network. The spokes dial the hub, never the reverse. There is no `LoadBalancer` service in the fleet and no address pool — the cluster side of the tunnel is **one NodePort, 30443**, on the chart's own Traefik Service.

Transit addressing, the WireGuard keys and the firewall rules live in [`nix-config`](https://github.com/Joker9944/nix-config), not here. This repo names only what Traefik has to agree with the edge about, in `schema.cue`: `#IngressSpoke`, `#WireGuardHubIP` (`10.100.0.254/32`) and `#EdgeNodePort`.

Three things have to line up, and each fails differently:

- **`nodeSelector` on `#IngressSpoke`** places the Traefik DaemonSet on exactly the nodes that terminate a tunnel. `mother` is an agent, runs no Traefik pod and is not a spoke — which is also why Traefik carries no [`#Reserved`](/platform/cluster-nyx.md) toleration any more.
- **`externalTrafficPolicy: Local`** keeps the hub's source address off kube-proxy's SNAT, and stops a packet arriving on a spoke from being forwarded to a node with no tunnel. Dropping it does not break connectivity; it silently replaces every client IP with a node's.
- **`proxyProtocol.trustedIPs` and `forwardedHeaders.trustedIPs`, both `#WireGuardHubIP`.** The hub speaks PROXY protocol; nothing else may. **This fails open.** Get the trusted range wrong and every request presents the hub's `10.100.0.254` — which `country-whitelist` reads as a local request and allows, so the whitelist passes the world while looking healthy. The access log is the test: a `ClientHost` of `10.100.0.254` means it did not take.

The `websecure` entrypoint keeps its name — every `router.entrypoints` annotation `#IngressAnnotations` writes names it — and moves to `exposedPort: 8443`. `web` is still an entrypoint but is not exposed on the Service: the edge's nginx answers `:80` itself.

# Traefik

Ingress is HTTPS-only through the `websecure` entrypoint. Every `Ingress` sets `traefik.ingress.kubernetes.io/router.tls: "true"`, names an entrypoint, names a middleware chain, and references the wildcard TLS secret from [PKI](/platform/certificates-and-pki.md).

The chart's `values.schema.json` closes the top level, so a values key a chart major has renamed away fails the HelmRelease outright rather than being ignored. That is what makes a major bump here a values migration rather than a version bump.

Two experimental plugins are loaded, both tracked by renovate against github-tags:

- `geoblock` (`github.com/PascalMinder/geoblock`) — backs the country whitelist.
- `oidc` (`github.com/lukaszraczylo/traefikoidc`) <!-- cSpell:ignore lukaszraczylo --> — puts [kanidm](/platform/identity-kanidm.md) in front of apps that have no OIDC support of their own. Session state lives in a dedicated `traefik-oidc-redis` replication cluster from the ot-helm Redis operator, which is why `traefik` needs the `redis` capability.

A `Middleware` names a plugin by its **registration key** — the `experimental.plugins.<name>` key, not the module path. `spec.plugin.traefikoidc` against a plugin registered as `oidc` builds nothing: Traefik logs `unknown plugin type` once as the router is built, leaves that router unmounted, and every request to it gets a plain 404 with `RouterName: "-"` in the access log. It never logs again, so a quiet log is not evidence the chain works — `geoblock` is the control, keyed consistently and therefore fine.

The converse also holds. Every Traefik pod logs a burst of `middleware ... does not exist` and `servers transport not found` within a few seconds of its own start: the Ingress provider builds routers before the kubernetesCRD provider has finished its first sync. It resolves itself and there is nothing to configure. Read those errors against the pod's `status.startTime` before believing them. One warning is likewise not actionable: Traefik logs the encoded-characters advisory unconditionally at start-up, before it reads any configuration, so no values change silences it.

# Middleware chains

`#Middlewares` installs the same set into every namespace, taking the namespace as a parameter; a bundle with no ingress switches it off. Two chains are meant to be referenced from an ingress:

| Chain                     | Composition                                                                                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `chain-basic`             | `basic-ratelimit` (600 avg / 400 burst) + `basic-secure-headers` (HSTS 2y, nosniff, XSS filter, `X-Forwarded-Proto: https`) + `compress` |
| `chain-country-whitelist` | `country-whitelist` + the three basic middlewares                                                                                        |

`country-whitelist` allows CH, DK and FR plus the tailnet, rejecting unknown countries. **The cluster networks are k3s's, not kubeadm's**: pods are `10.42.0.0/16` and services `10.43.0.0/16`, against the `10.244.0.0/16` and `10.96.0.0/12` a kubeadm cluster would use. The move off Talos changed both, and the old values survived in every workload that trusts the reverse proxy or firewalls its own egress; [`#PodCIDR`](/architecture/cue-layout.md) names them once.

There is no third chain and no bare middleware: `#Release` has no field for one, so an ingress that skips the rate limit, the secure headers and compression cannot be expressed. Everything Traefik serves is public, because an ingress that should not be is served from the tailnet instead.

The `basic-*` middlewares are ported from the TrueCharts Traefik chart and kept under their original names for compatibility with other TrueCharts charts still in use.

**A middleware is scoped to a router, not a path, and Traefik has no deny middleware.** An app serving something internal on the same port as its public UI therefore cannot simply not route it, and `extraMiddlewares` appends to the whole router. `replacePathRegex` is the only middleware that reads the path itself, so rewriting to a path the app does not serve turns the request into the app's own 404 — and a regex matching an ASP.NET route wants `(?i)`, because endpoint routing there is case-insensitive. Nothing in the fleet does this today; jellyfin did until [its metrics endpoint was switched off](/decisions/jellyfin-metrics-not-scraped.md), so this is the known answer rather than an established pattern.

# Naming the chain from an ingress

Middleware references are namespace-qualified (`<namespace>_<chain>@kubernetescrd`). `#IngressAnnotations` derives the prefix from the namespace it is handed, so an ingress cannot name a middleware that does not exist in its own namespace. That used to be the most common source of breakage here.

The underscore is `safeNaming`, on in the chart values. It applies to every name the **kubernetesCRD** provider generates — middlewares and the [kanidm](/platform/identity-kanidm.md) ServersTransport — joining namespace and name with `_` and skipping the normalization the legacy scheme applied; only that first separator changes, so `chain-country-whitelist` keeps its own dashes. Routers and services from the Ingress provider (`@kubernetes`) are untouched. The chart emits the flag only when it is true, so returning to the legacy `-` scheme means a raw `additionalArguments` entry, not `safeNaming: false` — that renders nothing and Traefik warns that the option is unset. Two sites write a reference outside `#IngressAnnotations`: the kanidm Service annotation, and a `mustReject` fixture in `cue/probe`.

# Tailnet ingress

The [tailscale operator](https://tailscale.com/kb/1236/kubernetes-operator) is a second ingress path, parallel to Traefik rather than behind it. An `Ingress` with `ingressClassName: tailscale` and a non-empty `tailscale.com/proxy-group` annotation is served by tailnet proxy pods — `shouldExpose` reads nothing else — which means it is **not** behind the middleware chains above: no rate limit, no secure headers, no whitelist. The tailnet is the perimeter instead, and nothing on it is reachable from the LAN without being on the tailnet.

It carries everything that is not public: pgadmin, qbittorrent, the longhorn dashboard, and kube-prometheus-stack's alertmanager and prometheus. `#Release.tailnet` switches a release over; `#TailnetIngress` holds the class, the proxy-group annotation and the host, which a foreign chart splices at its own path exactly as it splices `ingressAnnotations`. Under `tailnet` the middleware fields collapse to sentinels, so naming a chain there is a build error rather than a field nothing reads — see [the CUE layout](/architecture/cue-layout.md).

**The advertised name is `spec.tls[0].hosts[0]` cut at the first dot**, and the cut has to leave a valid DNS label. That is the whole of the hostname interface — there is no hostname annotation — and the `tls` block is mandatory despite naming no Secret, because it feeds two things:

- the name, which without it falls back to `<namespace>-<name>-ingress`;
- **rule matching.** A `spec.rules[].host` that is non-empty and does not equal the _full_ MagicDNS FQDN is discarded, one warning Event per rule. Discard them all and the handler map is empty: the Ingress still reconciles and still reports an ADDRESS, but serves nothing.

So the host has to be the FQDN, not the bare label the upstream example shows. That example omits the rule host entirely, which is the only other way to satisfy the comparison and is unavailable here — app-template requires `host` on a host entry, and longhorn, pgadmin4 and kube-prometheus-stack always write one. `#Release` derives the label from `host` exactly as the operator does and unifies the FQDN back, so a tailnet release left on a `vonarx.online` host conflicts at build time rather than reconciling into silence.

**No certificate is declared or stored.** Tailscale provisions and serves it, and `spec.tls[].secretName` is never read — which is why longhorn's chart writing `secretName` unconditionally whenever `ingress.tls` is set needs no postRenderer: the stale wildcard name is inert. The operator does reject more than one `tls` entry, or more than one host inside it.

The tailnet settings an Ingress depends on are not in this repo — MagicDNS, HTTPS Certificates and the policy-file grants. `tailscale-operator/tailscale-ingress.txt` is the runbook, in the spirit of the [kanidm](/platform/identity-kanidm.md) ones.

**Each Ingress is one Tailscale Service, `svc:` plus the cut label, and advertising one is a double opt-in action.** Without an `autoApprovers.services` entry for the proxy tag, every name waits on a manual approval in the admin console and the proxy pods never get the VIP in their AllowedIPs — the operator's own comment is the clearest statement of it. That, not the grants, is the setting a new tailnet ingress is most likely to be blocked on. Whether a tailnet-wide grant also reaches the Service is unsettled: `*` in a `dst` expands to Tailscale IPs and approved subnet routes, and the docs do not say whether a Service's Virtual IPs are inside that set. `dst: ["svc:<label>"]` is the unambiguous form if a name resolves but refuses to connect.

`cue/infrastructure/controllers/tailscale-config` holds the one `ProxyGroup`, named from `#TailnetProxyGroup` so it cannot drift from the annotation every ingress writes, at three replicas. The proxy pods run in the operator's own namespace, `tailscale`: the operator reads `OPERATOR_NAMESPACE` from its own `metadata.namespace` through a fieldRef and creates every proxy StatefulSet there, with no separate knob — which is why that namespace is named for the tailnet rather than for the operator. Nothing declares a capability on it: an `Ingress` is core API and applies cleanly against a missing ProxyGroup, so the coupling is at runtime — see [capability graph](/architecture/capability-graph.md).

**Spreading those replicas is a `ProxyClass` concern.** `ProxyGroup.spec` carries no scheduling fields at all, and the operator applies neither affinity rules nor topology spread constraints of its own, so three replicas may share one node. The `spread` ProxyClass supplies a `topologySpreadConstraint` over `kubernetes.io/hostname` and selects on a label it adds through `pod.labels` — the operator's own pod labels are not a documented interface. `nodeTaintsPolicy: Honor` keeps the [reserved node](/platform/cluster-nyx.md) out of the skew calculation, leaving three domains for three replicas.

# Pod DNS behind a VPN sidecar

The cluster serves no LAN DNS of its own; that moved off-cluster with the address pool.

Pods inherit the node's search domains, so every pod's `resolv.conf` carries the tailnet domain (`#TailnetDomain`, `stoat-herring.ts.net`) after the three `.cluster.local` entries, at `ndots:5`. That is harmless until a VPN sidecar owns the resolver.

gluetun points `resolv.conf` at its own server on `127.0.0.1` — one file, bind-mounted into every container of the pod and rewritten on each `DNS_UPDATE_PERIOD` — and answers **`NOERROR` with zero answers, not `NXDOMAIN`**, for any name it cannot resolve. Only `.cluster.local` gets a true `NXDOMAIN`. musl reads `NOERROR` as "the name exists, with no address of this type" and abandons the search walk there, so a relative lookup dies on the tailnet suffix and the absolute name is never queried. In qBittorrent every tracker then reports `Host not found (authoritative)` — Boost.Asio's rendering of `EAI_NODATA`, which reads like an upstream NXDOMAIN and is not one.

**Two tools lie about this.** `curl` in these images links c-ares (`curl -V` → `AsynchDNS`), which tolerates the bogus `NOERROR` and keeps walking; `nslookup` queries the name as given and never applies the search list at all. Both succeed while the app fails. Only `getaddrinfo` reproduces it, so test with that.

[qbittorrent](/architecture/app-template-pattern.md) is the fix's only site: `dnsPolicy: None` plus an explicit `searches` omitting the suffix. `dnsConfig.searches` under `ClusterFirst` only ever _appends_, so removing an inherited domain needs `None`, and `None` in turn requires an explicit `nameservers` — which hardcodes the cluster domain and the namespace into the package. Keeping `ndots:5` is deliberate: the walk now exhausts three `NXDOMAIN`s and reaches the absolute name, and short cluster names still resolve. Any other musl workload put behind gluetun needs the same treatment. <!-- cSpell:ignore ndots resolv musl NXDOMAIN NOERROR getaddrinfo NODATA Asio -->
