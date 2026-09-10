---
type: Reference
title: kanidm OIDC claim mapping
description: Which OIDC claim carries which kanidm attribute, which attributes never leave kanidm at all, and where the upstream book disagrees with the code.
tags: [kanidm, oidc, oauth2, claims, sso]
resource: cue/infrastructure/security/kanidm
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-10T20:20:00Z }
sources:
  - id: kanidm-oauth2
    resource: https://github.com/kanidm/kanidm/blob/v1.11.1/server/lib/src/idm/oauth2.rs
    title: kanidm — server/lib/src/idm/oauth2.rs
    last_modified: 2026-08-14
  - id: kanidm-account
    resource: https://github.com/kanidm/kanidm/blob/v1.11.1/server/lib/src/idm/account.rs
    title: kanidm — server/lib/src/idm/account.rs
    last_modified: 2026-08-14
  - id: kanidm-book-oauth2
    resource: https://github.com/kanidm/kanidm/blob/v1.11.1/book/src/integrations/oauth2.md
    title: kanidm book — OAuth2/OIDC
    last_modified: 2026-08-14
  - id: kanidm-book-claims
    resource: https://github.com/kanidm/kanidm/blob/v1.11.1/book/src/integrations/oauth2/custom_claims.md
    title: kanidm book — Custom Claim Maps
    last_modified: 2026-08-14
  - id: compact-jwt
    resource: https://docs.rs/compact_jwt/latest/compact_jwt/oidc/struct.OidcClaims.html
    title: compact_jwt — OidcClaims
  - id: user-oidc
    resource: https://github.com/nextcloud/user_oidc/blob/master/lib/Service/ProviderService.php
    title: Nextcloud user_oidc — ProviderService
---

Everything here is read off kanidm's source at the tag [`identity-kanidm`](/platform/identity-kanidm.md) pins, currently `1.11.1`. It is upstream behaviour, not repo configuration — re-verify against the tag when that image bumps.

# One pair of functions builds every claim

`s_claims_for_account` produces the standard claims, `extra_claims_for_account` the rest. The id_token path and the `/oauth2/openid/<client>/userinfo` endpoint call both with the same arguments,[^kanidm-oauth2] so a claim missing from the token is missing from userinfo too. There is no second endpoint to go fetch it from.

# The table

| Claim                     | kanidm attribute                                                | Gated on scope   |
| ------------------------- | --------------------------------------------------------------- | ---------------- |
| `sub`                     | `uuid`, always                                                  | `openid`         |
| `name`                    | `displayname`                                                   | none             |
| `preferred_username`      | `spn`, or `name` under `prefer-short-username`                  | none             |
| `email`, `email_verified` | `mail`, primary value only                                      | `email`          |
| `updated_at`              | the entry's last-modified changestamp                           | `profile`        |
| `groups`                  | uuid + spn (`groups`), spn (`groups_spn`), name (`groups_name`) | resp.            |
| `ssh_publickeys`          | `sshkeys`                                                       | `ssh_publickeys` |

`sub` is the UUID unconditionally — there is no setting that makes it the name or spn. `prefer-short-username` only moves `preferred_username` between `spn` and `name`; it is per client, and the six clients registered here set it while the four servarr ones do not. The same toggle also drives `username` in the token introspection response.

# The book disagrees with the code

The book files `name` and `preferred_username` under the `profile` scope.[^kanidm-book-oauth2] The code gates neither: `s_claims_for_account` sets both on every issued token, and `profile` decides only `updated_at`.[^kanidm-oauth2] A client requesting bare `openid` still receives both.

The book also lists `address` and `phone` as supported scopes. Nothing populates their claims.

# Attributes that never leave kanidm

`legalname` is the one that bites: the `Account` struct the OAuth2 path builds has no such field, so it is never read off the entry.[^kanidm-account] No scope, claim map or endpoint can surface it — a client that wants a person's legal name reads LDAP or does without.

The same holds for every claim `compact_jwt`'s `OidcClaims` defines that kanidm leaves at `None`[^compact-jwt] — `given_name`, `family_name`, `middle_name`, `nickname`, `profile`, `picture`, `website`, `gender`, `birthdate`, `zoneinfo`, `locale`, `phone_number`, `address`. Serde drops them, so they are absent rather than null.

# Claim maps are keyed on groups, not attributes

`kanidm system oauth2 update-claim-map <client> <claim> <group> [values]...` binds a claim name to static values, selected by group membership; values merge when an account is in several mapped groups. `update-claim-map-join` picks `array` (default), `csv` or `ssv` for how they serialise.[^kanidm-book-claims]

This is not an attribute-mapping mechanism. The value comes from the group, so a claim map cannot carry anything that varies per person.

# Picking a stable identifier

A consumer keys its local user record on whichever claim it maps to its user ID, so that claim has to be immutable — a client that does not implement rename provisions a second account and orphans the first. `name` carries `displayname`, which is free text a person edits, so it is the wrong choice there. Use `sub`, or `preferred_username` when a readable ID is worth treating renames as a manual migration.

Nextcloud's `user_oidc` defaults `mappingUid` to `sub` and `mappingDisplayName` to `name`,[^user-oidc] which is already that pairing; the other clients registered through [`identity-kanidm`](/platform/identity-kanidm.md) name the two settings differently.

[^kanidm-oauth2]: kanidm — `server/lib/src/idm/oauth2.rs`

[^kanidm-account]: kanidm — `server/lib/src/idm/account.rs`

[^kanidm-book-oauth2]: kanidm book — OAuth2/OIDC

[^kanidm-book-claims]: kanidm book — Custom Claim Maps

[^compact-jwt]: compact_jwt — `OidcClaims`

[^user-oidc]: Nextcloud user_oidc — ProviderService
