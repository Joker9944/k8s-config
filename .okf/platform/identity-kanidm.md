---
type: Infrastructure
title: Identity — kanidm
description: The cluster's OIDC/LDAP provider, and why every consumer ships a kanidm-oidc.txt that nothing applies.
tags: [kanidm, oidc, sso, identity]
resource: cue/infrastructure/security/kanidm
status: stable
generated: { by: claude-code/fable-5, at: 2026-09-11T15:00:00Z }
---

# Deployment

kanidm is the sole member of the `security` tier. It runs as a StatefulSet from `app-template` at `idm.vonarx.online`, HTTPS on 8443 and LDAP on 3636.

It is the only workload that terminates TLS itself: `KANIDM_TLS_CHAIN`/`KANIDM_TLS_KEY` point at a wildcard certificate minted into its own namespace by [`#NamespaceCert`](/architecture/cue-layout.md), and a Traefik `ServersTransport` (declared through `rawResources`, trusting `nyx-ca-cert-bundle`) makes Traefik accept that certificate on the backend hop. The namespace reaches the transport, the annotations and the `serverName` as an ordinary field reference. It names the bundle through `rootCAs`, one entry per Secret or ConfigMap, each holding its certificate under `tls.ca` or `ca.crt`.

`KANIDM_TRUST_X_FORWARD_FOR: true` is what makes rate limiting and audit logs see real client addresses behind Traefik. Health probes exec `kanidmd scripting healthcheck` rather than hitting HTTP.

# Client registration is manual

Eleven workloads ship a `kanidm-oidc.txt` beside their package: audiobookshelf, gotify, jellyfin, komga, nextcloud, opencloud and kube-prometheus-stack (for Grafana) at the package root, and the four servarr apps — prowlarr, radarr-standard, sonarr-anime, sonarr-standard — under `servarr/kanidm-oidc/<app>.txt`, because that package is flat. Each holds the verbatim `kanidm` CLI commands to create the OAuth2 client, add redirect URLs, create `<app>_admins`/`<app>_users` groups, add a shared tier group as a _member_ of each (`media_*`, `cloud_*` or `monitoring_*`, matching the app's Flux tier), and set scope maps. What a granted scope actually puts in the token is [claim mapping](/reference/oidc-claim-mapping.md). Membership therefore flows tier group → app group; the tier groups themselves are created out-of-band. gotify's file also registers the Android app's `gotify://oidc/callback`: kanidm files a non-`http(s)` redirect as an _opaque origin_ and matches it on a confidential client too, where the book reads as if custom schemes were public-client only. opencloud is the only entry that is **public** rather than confidential — its web UI is a browser SPA whose chart carries no client-secret setting — and the only one whose single client serves four apps: kanidm's issuer URL and token signing keys are per client while OpenCloud validates against one `OC_OIDC_ISSUER`, so a client per app yields tokens the proxy rejects. Web, desktop, Android and iOS all authenticate as `openclouddesktop`, put there by OpenCloud's own webfinger service, which hands each platform a `client_id` in place of the vendor-fixed one it ships with. Its desktop app needs `enable-localhost-redirects` for the ephemeral port it listens on. It is also the only one whose authorisation is driven by a claim map: the proxy reads a `roles` claim and matches `opencloudAdmin`/`opencloudUser`, so the scope map has to grant `roles` as well.

**Nothing in the repo applies them.** No package reads them, and kanidm has no declarative client CRD here. Deploying an app with SSO therefore takes two steps: reconcile the manifests, then replay the file by hand against a running kanidm. The client secret then has to be put into the app's [SOPS secret](/workflows/secrets-sops.md) separately — the file does not record where it goes. A public client has none, but opencloud's file carries a second manual step: it is kanidm's only LDAP consumer, reading users and groups over `kanidm-ldaps:636` (read-only, `dn=token` binding with a service-account api token), and that token is what goes into its [SOPS secret](/workflows/secrets-sops.md).

Apps with no OIDC support of their own are fronted by Traefik's `oidc` plugin instead; see [ingress](/platform/networking-and-ingress.md).
