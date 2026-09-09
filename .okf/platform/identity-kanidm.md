---
type: Infrastructure
title: Identity — kanidm
description: The cluster's OIDC/LDAP provider, and why every consumer ships a kanidm-oidc.txt that nothing applies.
tags: [kanidm, oidc, sso, identity]
resource: cue/infrastructure/security/kanidm
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T15:00:00Z }
---

# Deployment

kanidm is the sole member of the `security` tier. It runs as a StatefulSet from `app-template` at `idm.vonarx.online`, HTTPS on 8443 and LDAP on 3636.

It is the only workload that terminates TLS itself: `KANIDM_TLS_CHAIN`/`KANIDM_TLS_KEY` point at a wildcard certificate minted into its own namespace by [`#NamespaceCert`](/architecture/cue-layout.md), and a Traefik `ServersTransport` (declared through `rawResources`, trusting `nyx-ca-cert-bundle`) makes Traefik accept that certificate on the backend hop. The namespace reaches the transport, the annotations and the `serverName` as an ordinary field reference. It names the bundle through `rootCAsSecrets`, which `rootCAs` (secrets or ConfigMaps) deprecates; both ship in the CRD, but `rootCAsSecrets` works for the whole Traefik v3 line and is only removed in v4, so it stays until then.

`KANIDM_TRUST_X_FORWARD_FOR: true` is what makes rate limiting and audit logs see real client addresses behind Traefik. Health probes exec `kanidmd scripting healthcheck` rather than hitting HTTP.

# Client registration is manual

Nine workloads ship a `kanidm-oidc.txt` beside their package: audiobookshelf, jellyfin, komga, nextcloud and kube-prometheus-stack (for Grafana) at the package root, and the four servarr apps — prowlarr, radarr-standard, sonarr-anime, sonarr-standard — under `servarr/kanidm-oidc/<app>.txt`, because that package is flat. Each holds the verbatim `kanidm` CLI commands to create the OAuth2 client, add redirect URLs, create `<app>_admins`/`<app>_users` groups, add a shared tier group as a _member_ of each (`media_*`, `cloud_*` or `monitoring_*`, matching the app's Flux tier), and set scope maps. Membership therefore flows tier group → app group; the tier groups themselves are created out-of-band.

**Nothing in the repo applies them.** No package reads them, and kanidm has no declarative client CRD here. Deploying an app with SSO therefore takes two steps: reconcile the manifests, then replay the file by hand against a running kanidm. The client secret then has to be put into the app's [SOPS secret](/workflows/secrets-sops.md) separately — the file does not record where it goes.

Apps with no OIDC support of their own are fronted by Traefik's `oidc` plugin instead; see [ingress](/platform/networking-and-ingress.md).

# Observability

A Grafana dashboard for kanidm's logs ships as `files/kanidm-logs.json`, turned into a ConfigMap labelled `grafana_dashboard: "1"` by `#ConfigMapFiles` in the app's own package. That is the repo-wide convention for dashboards — see [observability](/platform/observability.md).
