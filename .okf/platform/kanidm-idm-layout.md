---
type: Infrastructure
title: kanidm IDM layout
description: The groups, OAuth2 clients and service accounts that live only in kanidm's database, and how membership flows from tier groups to app groups.
tags: [kanidm, groups, oauth2, identity]
resource: cue/infrastructure/security/kanidm-cluster
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-14T21:00:00Z }
---

# Groups

People join tier groups only. Each tier group is a member of the app groups its tier's clients scope-map, so a tier grants every app in it.

| Tier group          | Member of                                                                    |
| ------------------- | ---------------------------------------------------------------------------- |
| `media_admins`      | `audiobookshelf_admins`, `jellyfin_admins`, `komga_admins`, `servarr_admins` |
| `media_users`       | `audiobookshelf_users`, `jellyfin_users`, `komga_users`                      |
| `cloud_admins`      | `opencloud_admins`                                                           |
| `cloud_users`       | `opencloud_users`                                                            |
| `monitoring_admins` | `gotify_admins`, `grafana_admins`                                            |
| `monitoring_users`  | `gotify_users`, `grafana_users`                                              |

`servarr_admins` serves all four servarr clients and has no `_users` counterpart. Grafana has no viewer tier: its claim map gives `grafana_users` `Editor` and `grafana_admins` `Admin`, since Editor is what unlocks Explore and Drilldown and nothing saved in the UI survives [provisioning](/platform/observability.md). The tier groups and `servarr_admins` are created by hand; every other app group comes from its app's `kanidm-oidc.txt` ([client registration](/platform/identity-kanidm.md)).

# OAuth2 clients

| Client                                                           | Type   | Scope-mapped groups                   |
| ---------------------------------------------------------------- | ------ | ------------------------------------- |
| `audiobookshelf`, `jellyfin`, `komga`                            | basic  | `<client>_admins`, `<client>_users`   |
| `gotify`, `grafana`                                              | basic  | `<client>_admins`, `<client>_users`   |
| `prowlarr`, `radarr-standard`, `sonarr-anime`, `sonarr-standard` | basic  | `servarr_admins`                      |
| `openclouddesktop`                                               | public | `opencloud_admins`, `opencloud_users` |

Scopes, claim maps and redirect URLs are in each client's `kanidm-oidc.txt`; what they put in a token is [claim mapping](/reference/oidc-claim-mapping.md). Every client has strict redirect URIs and none has a supplementary scope map.

# Service accounts

Beyond the builtins, only `opencloud`: managed by `opencloud_admins`, a member of `idm_account_mail_read`, holding one read-only API token with no expiry for its LDAPS bind. The builtin `anonymous` account is expired, so unauthenticated reads are refused.
