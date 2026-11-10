---
type: Decision
title: Jellyfin's SSO plugin is the maintained fork
description: Jellyfin authenticates through K0lin/jellyfin-plugin-sso, the continuation of 9p4's archived plugin, rather than the newer jellyfin-plugin-oidc.
tags: [jellyfin, sso, oidc, plugins, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-10T19:10:00Z }
stale_after: 2027-05-10
---

# Decision

Jellyfin's OIDC login comes from
[K0lin/jellyfin-plugin-sso](https://github.com/K0lin/jellyfin-plugin-sso),
installed as `SSO Authentication` from that fork's own plugin repository. 9p4's
original was archived in May 2026 naming no successor; the fork carries the same
plugin GUID — `505ce9d1-d916-42fa-86ca-673ef241d7df` — so adopting it is a
version upgrade, not a migration.

Not taken: [Ezeqielle/jellyfin-plugin-oidc](https://github.com/Ezeqielle/jellyfin-plugin-oidc). <!-- cSpell:ignore Ezeqielle Kolin Abi -->

# Why

The shared GUID is what decides the cost. One plugin identity means one
`SSO-Auth.xml` and the same `/sso/OID/redirect/kanidm` callback, so
[kanidm's client](/platform/identity-kanidm.md) needs no edit and the canonical
links binding kanidm SPNs to Jellyfin user GUIDs carry over untouched.

The fork also ships the Jellyfin 12 build the cluster runs against — `targetAbi`
`12.0.0.0` on net10. The alternative's releases target 10.11; its maintainer
reports the plugin loads on 12 unchanged, but the 12-targeted branch is parked
while both projects discuss merging into one plugin. It is a separate plugin
identity besides: no link table, users resolved on `preferred_username` alone,
and its role mappings rewrite a user's whole policy — admin flag and library set
included — on every login.

# What it costs

Trust moves from an archived upstream to one maintainer's fork. Should the
consolidation land on the other codebase, the migration this defers comes back:
new redirect URLs, role mappings in place of the SPN-keyed role lists, and users
matched by name rather than by link.

Which file the plugin repository URL lives in, and why an upgrade needs a
restart, are in [Jellyfin's config](/workflows/jellyfin-config.md) — the
settings themselves stay
[undeclared](/decisions/jellyfin-config-not-declared.md).
