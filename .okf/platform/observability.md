---
type: Infrastructure
title: Observability
description: The metrics, logs and notification path — kube-prometheus-stack, Loki fed by Alloy, and Gotify running a repo-built image.
tags: [prometheus, grafana, loki, alloy, gotify, alerting]
resource: cue/infrastructure/observability
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-10T14:35:00Z }
---

# The tier

Four workloads, chained by `dependsOn` back to [Garage](/platform/storage.md):

```
garage → loki → alloy
kube-prometheus-stack → gotify
```

- **kube-prometheus-stack** — Prometheus, Alertmanager and Grafana. Grafana authenticates against [kanidm](/platform/identity-kanidm.md); the Prometheus and Alertmanager UIs sit behind `chain-network-internal-whitelist` while Grafana takes the country whitelist.
- **loki** — `SimpleScalable`, chunks and indexes in Garage over the in-cluster endpoint, `s3ForcePathStyle: true`. Grafana and Alloy both address it through `loki-gateway`, because the split targets put the ruler on `loki-backend`: a `loki-read` URL serves every query path and so looks correct, but 404s the alerting page's `/prometheus/api/v1/rules`.
- **alloy** — the log shipper.
- **gotify** — the notification sink. It authenticates against [kanidm](/platform/identity-kanidm.md) natively, with local password auth left on as break-glass.

# Log pipeline

`cue/infrastructure/observability/alloy/files/config.alloy` is a `#ConfigMapFiles` source, not a chart value. It discovers pods via `discovery.kubernetes` (role `pod`), relabels `__meta_kubernetes_*` into `namespace`, `pod`, `container`, `node` and `app` (from `app.kubernetes.io/name`), derives `job` as `<namespace>/<container>`, and writes to `loki-gateway.loki.svc.cluster.local`.

Two sources feed one `loki.write.default`: those pod logs, and cluster events through `loki.source.kubernetes_events` (`job_name` `kubernetes/events`, JSON). Both stamp a static `cluster: nyx`; the pod branch additionally derives `container_runtime` from the scheme prefix of the container id.

**Both sources need the clustering ring, and it takes two halves.** Alloy is a DaemonSet and `discovery.kubernetes` carries no node filter, so every replica sees every pod. `loki.source.kubernetes` shards targets across peers only when the component's `clustering` block is on *and* `alloy.clustering.enabled` is set, which is what builds the `alloy-cluster` headless Service the chart's `--cluster.join-addresses` names; either half alone is inert. With the ring off, four replicas shipped identical lines and nothing downstream showed it — Loki silently drops an exact duplicate of `(timestamp, line)` within a stream, and the pod branch labels `node` from the target rather than the shipper, so the four copies land in one stream. `loki.source.kubernetes_events` shards per namespace and `namespaces` is empty, so all replicas hold the same all-namespaces target and the ring is the only thing electing a single collector. The tell is `loki_write_sent_entries_total`, near-equal across all four pods.

The pod branch is not generic. Its `loki.process` carries per-app stages — healthcheck drops for kanidm (`| uri: /status |`) and audiobookshelf (`Received ping`), and `stage.regex` pulling `level` and `message` out of kanidm, audiobookshelf and servarr lines, the last needing `stage.multiline` because those logs wrap. Onboarding a noisy app means adding a `stage.match` here, not changing the discovery rules.

**Those `stage.regex` captures are discarded.** No `stage.labels` or `stage.structured_metadata` follows them, so `level`, `message` and the rest never leave the extracted map. The fleet's only log level is therefore Loki's own — `detected_level` structured metadata, from `discover_log_levels`, which nothing here disables. It is uniform across every namespace, at the price of being a heuristic: `unknown` covers roughly half the volume. Structured metadata is invisible to the label API (`label_values(detected_level)` is empty), so a level picker has to carry a hardcoded list.

The dev shell ships `grafana-alloy` so this file can be checked with `alloy fmt`/`alloy validate` before committing.

# Alerting path

Alertmanager → `gotify-alertmanager-bridge` (`ghcr.io/druggeri/alertmanager_gotify_bridge`) <!-- cSpell:ignore druggeri --> → Gotify.

The route tree is the chart's: naming `route.routes` replaces the default list wholesale, so Watchdog — the heartbeat that must never stop firing — has to be re-declared to `null` beside any addition.

The bridge chooses its Gotify application from a `?token=` on the webhook URL, so the receiver's URL is a credential and is not written in the release. It sets `url_file` instead, against a SOPS Secret named in `alertmanagerSpec.secrets`, which the operator mounts at `/etc/alertmanager/secrets/<name>/`. prometheus-operator re-marshals the raw config through its own structs and silently drops what it does not model: it does model `url_file`, but strips it below Alertmanager 0.26.0 and discards it outright when `url` is set alongside. Alertmanager reads the file inside each notification rather than at config load, so rotating the Secret needs no restart. The bridge's own `GOTIFY_TOKEN` is only the fallback for a request that carries no `?token=`; it holds a literal placeholder because the bridge exits 1 when it is unset, not because anything reads it.

Gotify itself runs `ghcr.io/joker9944/gotify-custom`, an image **built by this repo** so that the `gotify-slack-webhook` Go plugin is compiled against a matching gotify-server ABI. That constraint is the reason `pkgs/gomod-cap.nix` exists — see [images and CI](/workflows/images-and-ci.md). Gotify keeps state in its own CNPG cluster and uses `ghcr.io/joker9944/postgresql-client`, another repo-built image, as a helper container.

**v3 configures from the environment only, and a list value is one bare CSV line.** The v2 `[a,b]` form still parses — as a single element with the brackets in it. That is silent both ways: gin discards the error from `SetTrustedProxies`, so a bracketed CIDR just leaves `X-Forwarded-For` unread, and CORS origins are unanchored regexes, where `[gotify.vonarx.online]` is a character class that matches almost any origin.

# Coverage gaps

**`NodeMemoryHighUtilization` is a local rule, not the chart's.** Linux does not count the ZFS ARC in `MemAvailable`, and [mother](/platform/cluster-nyx.md) holds ~54 of its 62 GiB there, so the stock expression reads 95% on a host that is 11% used; the replacement adds back ARC above `arc_c_min` and contributes 0 where there is no ARC, so one rule still covers the fleet. `defaultRules` reaches `for` and `severity` per rule but never the expression, so a wrong default can only be disabled and re-declared — `defaultRules.disabled` alongside `additionalPrometheusRulesMap`, whose PrometheusRule carries the `release` label the default `ruleSelector` wants and a hand-written one would not. The node-exporter-mixin dashboards read `MemAvailable` directly, so they still show that node near 95% and disagree with the alert. That divergence is accepted — they are chart-rendered with no per-dashboard toggle, and correcting them means owning a replacement node dashboard.

Grafana's **Alertmanager datasource has no backend**, so `/api/datasources/uid/alertmanager/health` answers `HTTP 500 plugin.unavailable` every time ([grafana#83794](https://github.com/grafana/grafana/issues/83794)). The datasource provisions and works in the browser; only the server-side health API is unimplemented for this type. A health sweep — `check_datasources_health` on the MCP server — therefore reports it broken on a healthy cluster. Not a fault to chase.

# Dashboards

Dashboards live with the app they describe, not with Grafana: a JSON file under the app's `files/`, turned into a ConfigMap by `#ConfigMapFiles` carrying `grafana_dashboard: "1"` plus `app.kubernetes.io/name` and `app.kubernetes.io/instance` labels. `cue/infrastructure/observability/loki/files/logs.json` is the worked example, and the exception that proves the rule: it filters every namespace by `detected_level`, so it describes Loki's contents rather than any one app and lives with Loki.

That is not just a convention — Grafana runs with no persistence, its `storage` volume an `emptyDir`, so `grafana.db` dies with the pod. Dashboards and datasources are re-provisioned at start-up and the admin user is re-created from the `grafana-admin` Secret, but everything else held in that database — service accounts and their tokens, silences, stars, preferences — is gone. A dashboard authored in the UI is a scratch buffer, not a change, and the read-only MCP server's service account has to be re-minted by hand after every restart — Grafana provisions no service accounts ([grafana#82987](https://github.com/grafana/grafana/issues/82987)), so `kube-prometheus-stack/grafana-service-account.txt` carries the procedure.
