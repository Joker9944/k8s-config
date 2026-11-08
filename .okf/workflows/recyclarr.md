---
type: Reference
title: Recyclarr
description: How recyclarr reaches the *arr instances, what it cannot manage, and why a broken sync is easy to miss.
tags: [recyclarr, servarr, trash-guides, cronjob]
resource: cue/apps/media/servarr
status: stable
generated: { by: claude-code/opus-5, at: 2026-11-08T00:00:00Z }
---

A daily CronJob in the servarr namespace running `recyclarr sync` against the two
Sonarr instances and Radarr, with [TRaSH-Guides](https://github.com/TRaSH-Guides/Guides)
as the source of custom formats, quality profiles and naming formats. Its config
is `files/recyclarr.yml`, a `#ConfigMapFiles` source — see
[the app-template pattern](/architecture/app-template-pattern.md).

# Reaching the instances

`base_url` and `api_key` are both `!env_var` references. The env is built in
`servarr.cue` by comprehension over the `_arrs` entries flagged
`recyclarrSync`, so the URL is assembled from the same `name`/`app`/`port` that
the chart builds the Service from and the API key is read from the
`<name>-api-key` Secret the *arr itself uses. The instance key is `name` with
underscores, derived rather than written down; **the config cannot be embedded as
YAML to check that against it**, because CUE rejects the `!env_var` tag. There is no second copy of a key,
and a renamed controller cannot leave the URL pointing at a name that no longer
resolves.

**Recyclarr resolves `<instance>_base_url` and `<instance>_api_key` implicitly
from `/config/secrets.yml` whenever the properties are omitted from the config**,
which is why a working config can contain no `api_key` line at all. The trap is
the failure mode: with neither the secret nor an explicit value, recyclarr logs
no error, processes **no instances**, and exits 0. A sync that silently did
nothing looks exactly like a sync with nothing to do.

# What it cannot manage

A Radarr quality profile's **language is not in recyclarr's schema** — the whole
of `quality_profiles` is `name`, `qualities`, `quality_definition`,
`quality_sort`, `score_set`, `min_format_score`, `min_upgrade_format_score`,
`reset_unmatched_scores`, `trash_id` and `upgrade`. The `(German)` and
`(Korean)` profiles are therefore byte-identical to `(Standard)` in this repo and
differ only by a field set by hand in Radarr's UI. A profile recyclarr has just
created is an English one until someone changes it. Sonarr has no language field
on a quality profile at all, which is why its profiles have no language variants.

# Checking it

There is no offline validation: `recyclarr config` offers only `create` and
`list`. The only thing that validates this config is a run against the live
instances, so `recyclarr sync --preview` — read-only — is the way to test a
change, and the daily job is what catches drift. Guide-side renames break the
config with no commit in this repo, which is how `media_naming: jellyfin` became
invalid when TRaSH split the preset into `jellyfin-imdb` / `jellyfin-tmdb` /
`jellyfin-tvdb`.

Note the asymmetry when reading sync output: a profile named in
`assign_scores_to` but defined nowhere is a **warning**, while an invalid naming
format is an **error**. Neither is visible if the Job is collected before anyone
looks — see the TTL trap in [observability](/platform/observability.md).
