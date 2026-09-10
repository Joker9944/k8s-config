---
type: Infrastructure
title: Observability
description: The metrics, logs and notification path — kube-prometheus-stack, Loki fed by Alloy, and Gotify running a repo-built image.
tags: [prometheus, grafana, loki, alloy, gotify, alerting]
resource: cue/infrastructure/observability
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-10T16:58:00Z }
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

**Both sources need the clustering ring, and it takes two halves.** Alloy is a DaemonSet and `discovery.kubernetes` carries no node filter, so every replica sees every pod. `loki.source.kubernetes` shards targets across peers only when the component's `clustering` block is on _and_ `alloy.clustering.enabled` is set, which is what builds the `alloy-cluster` headless Service the chart's `--cluster.join-addresses` names; either half alone is inert. With the ring off, four replicas shipped identical lines and nothing downstream showed it — Loki silently drops an exact duplicate of `(timestamp, line)` within a stream, and the pod branch labels `node` from the target rather than the shipper, so the four copies land in one stream. `loki.source.kubernetes_events` shards per namespace and `namespaces` is empty, so all replicas hold the same all-namespaces target and the ring is the only thing electing a single collector. The tell is `loki_write_sent_entries_total`, near-equal across all four pods.

# Per-workload pipelines

**A workload's log handling lives in its own package.** `alloy run` is pointed at a directory rather than a file, and alloy loads every `*.alloy` in it (no recursion) as **one graph**, so a file dropped in beside the base config is live config that can reference the base's components by name. `#AlloyPipeline` renders one into a ConfigMap in the workload's own namespace; a `kiwigrid/k8s-sidecar` pair in the alloy pod — `METHOD=LIST` as an init container so the base is on disk before alloy starts, `METHOD=WATCH` alongside it to reload on change — collects every ConfigMap labelled `alloy_config` from every namespace into `/etc/alloy.d`. Alloy's ClusterRole already grants cluster-wide `configmaps` get/list/watch and a sidecar shares the pod ServiceAccount, so this needs no RBAC of its own. servarr is the worked example.

The base keeps the parts that are genuinely shared: `discovery.relabel.k8s_pod_logs` holds the standard label rules, which a workload file narrows rather than repeats, and `loki.process.common` is the single place `cluster` is stamped. Which pods a workload claims is a **label, not a name in the base config** — `logs.vonarx.online/pipeline` — so the generic branch keeps only pods where it is empty and alloy never learns what workloads exist. `#AlloyPipeline` emits that label and the ConfigMap key from one `app` field, which is also what stops two workloads writing the same filename into the shared directory.

**One bad file stops the whole fleet's logs.** The graph is all-or-nothing: a dangling reference in any file fails the load. A reload survives it — alloy keeps the last good config — but a pod restart crashloops, so the failure surfaces later than the edit that caused it. `checks.alloyValidate` assembles the same union the sidecar delivers and rejects it before it can reach a node; that check is what makes this layout safe, not a convenience. Component labels are a second namespace it guards — `#AlloyPipeline` makes filenames unique but two workloads can still declare the same `loki.process "logs"`.

The claim label is the destructive half: a pod carrying it leaves the generic branch whether or not anything picked it up, so a pipeline that fails to load loses that workload's logs rather than falling back. **Accepted, not overlooked.** Inverting it — base keeps everything, workload files drop what they duplicate — costs double API tailing on every claimed pod forever to cover a window only an edit can open, and these files change only when an app changes its log format. Verify a new pipeline loaded when you add one; that is the whole mitigation. Migrating a workload also double-ships its lines once, in the window where both branches still hold the pod, and Loki does not collapse the pair — the per-app expression strips the trailing newline with `\s*$` and the generic branch does not, so the copies differ by a byte and the exact-duplicate drop misses them. It clears on the next relabel evaluation.

`alloy.configMap.key` is `../alloy.d`. The chart interpolates it into `run /etc/alloy/<key>` and hardcodes the config volume as a ConfigMap, so escaping the directory is the only way to point `run` at a path a sidecar can write; the ConfigMap stays mounted at `/etc/alloy` where nothing reads it. A post-render patch is the obvious alternative and is worse — the arg is addressable only by index, so a chart that inserts a flag ahead of it rewrites the wrong one silently. The real fix is upstream and unmerged: [alloy#1176](https://github.com/grafana/alloy/issues/1176), open since 2024. `configReloader` is off — it watches `/etc/alloy`, which alloy no longer reads.

# Log levels

**Every `stage.regex` here wants `(?s)` and a `\s*$` tail.** Lines arrive with a trailing newline and RE2's `$` matches only end-of-text — unlike Perl it does not match before a final newline — so `.+$` never reaches its anchor, and a `stage.regex` that matches nothing is silent: no captures, no error. The defect survives as long as the captures are unused and surfaces the moment a `stage.structured_metadata` is added for them to feed. That same silence is useful: a miss leaves the extracted map untouched, so an **optional** field belongs in a second pass over `message` rather than an optional group, which writes the empty string and stamps it on every line that lacks the field. Fixed widths are the related trap — kanidm's tracing-forest output pads the level out to a column and indents children past it, so only `\s+` fits every depth.

**kanidm's records are span trees, not lines.** `stage.multiline` folds every line sharing a kopid into one entry — tracing-forest buffers a tree and writes it on span close, so they are always contiguous — with roots identified by carrying no box-drawing glyph where children do; the negated class has to exclude the pad space as well, or ` +` gives one back, every child reads as a root and nothing folds. Its `detected_level` is therefore the **worst level in the request**, not the level of a line, and the root's `method`, URI path and `status_code` reach Loki as structured metadata. Leave `max_lines` at its default: `max_line_size` is 256KB with `max_line_size_truncate` off, so an oversized record is discarded rather than trimmed.

**A `level` that reaches Loki has to be lowercase.** `discover_log_levels` prefers the field over its own heuristic and copies the case it is given, and the [logs dashboard](/platform/observability.md) matches `detected_level` against a hardcoded lowercase list with `=~`, which is case-sensitive — so an `Info` is a line the dashboard silently cannot see. A `stage.template` with `ToLower` between the regex and the structured-metadata stage is what keeps a workload inside that convention.

Everywhere else the only log level is Loki's own — `detected_level` structured metadata, from `discover_log_levels`, which nothing here disables. It is uniform across every namespace, at the price of being a heuristic: `unknown` covers roughly half the volume. Structured metadata is invisible to the label API (`label_values(detected_level)` is empty), so a level picker has to carry a hardcoded list.

Two gates cover these files, failing for different reasons. `alloy fmt -w` runs in pre-commit beside `cue-fmt`, so formatting is canonical and auto-fixed rather than matched by eye — it loops because `alloy fmt` takes at most one file and pre-commit passes the batch. `checks.alloyValidate` owns semantics: it assembles the same union the sidecar delivers and rejects a dangling cross-file reference before it can reach a node. It parses stage templates too — an unknown function or a missing `{{ end }}` fails there rather than at runtime.

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
