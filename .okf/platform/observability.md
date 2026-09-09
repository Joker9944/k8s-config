---
type: Infrastructure
title: Observability
description: The metrics, logs and notification path — kube-prometheus-stack, Loki fed by Alloy, and Gotify running a repo-built image.
tags: [prometheus, grafana, loki, alloy, gotify, alerting]
resource: cue/infrastructure/observability
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T19:18:00Z }
---

# The tier

Four workloads, chained by `dependsOn` back to [Garage](/platform/storage.md):

```
garage → loki → alloy
kube-prometheus-stack → gotify
```

- **kube-prometheus-stack** — Prometheus, Alertmanager and Grafana. Grafana authenticates against [kanidm](/platform/identity-kanidm.md); the Prometheus and Alertmanager UIs sit behind `chain-network-internal-whitelist` while Grafana takes the country whitelist.
- **loki** — chunks and indexes in Garage over the in-cluster endpoint, `s3ForcePathStyle: true`.
- **alloy** — the log shipper.
- **gotify** — the notification sink. It authenticates against [kanidm](/platform/identity-kanidm.md) natively, with local password auth left on as break-glass.

# Log pipeline

`cue/infrastructure/observability/alloy/files/config.alloy` is a `#ConfigMapFiles` source, not a chart value. It discovers pods via `discovery.kubernetes` (role `pod`), relabels `__meta_kubernetes_*` into `namespace`, `pod`, `container`, `node` and `app` (from `app.kubernetes.io/name`), derives `job` as `<namespace>/<container>`, and writes to `loki-gateway.loki.svc.cluster.local`.

Two sources feed one `loki.write.default`: those pod logs, and cluster events through `loki.source.kubernetes_events` (`job_name` `kubernetes/events`, JSON). Both stamp a static `cluster: nyx`; the pod branch additionally derives `container_runtime` from the scheme prefix of the container id.

The pod branch is not generic. Its `loki.process` carries per-app stages — healthcheck drops for kanidm (`| uri: /status |`) and audiobookshelf (`Received ping`), and `stage.regex` pulling `level` and `message` out of kanidm, audiobookshelf and servarr lines, the last needing `stage.multiline` because those logs wrap. Onboarding a noisy app means adding a `stage.match` here, not changing the discovery rules.

The dev shell ships `grafana-alloy` so this file can be checked with `alloy fmt`/`alloy validate` before committing.

# Alerting path

Alertmanager → `gotify-alertmanager-bridge` (`ghcr.io/druggeri/alertmanager_gotify_bridge`) <!-- cSpell:ignore druggeri --> → Gotify.

The bridge chooses its Gotify application from a `?token=` on the webhook URL, so the receiver's URL is a credential and is not written in the release. It sets `url_file` instead, against a SOPS Secret named in `alertmanagerSpec.secrets`, which the operator mounts at `/etc/alertmanager/secrets/<name>/`. prometheus-operator re-marshals the raw config through its own structs and silently drops what it does not model: it does model `url_file`, but strips it below Alertmanager 0.26.0 and discards it outright when `url` is set alongside. Alertmanager reads the file inside each notification rather than at config load, so rotating the Secret needs no restart. The bridge's own `GOTIFY_TOKEN` is only the fallback for a request that carries no `?token=`; it holds a literal placeholder because the bridge exits 1 when it is unset, not because anything reads it.

Gotify itself runs `ghcr.io/joker9944/gotify-custom`, an image **built by this repo** so that the `gotify-slack-webhook` Go plugin is compiled against a matching gotify-server ABI. That constraint is the reason `pkgs/gomod-cap.nix` exists — see [images and CI](/workflows/images-and-ci.md). Gotify keeps state in its own CNPG cluster and uses `ghcr.io/joker9944/postgresql-client`, another repo-built image, as a helper container.

**v3 configures from the environment only, and a list value is one bare CSV line.** The v2 `[a,b]` form still parses — as a single element with the brackets in it. That is silent both ways: gin discards the error from `SetTrustedProxies`, so a bracketed CIDR just leaves `X-Forwarded-For` unread, and CORS origins are unanchored regexes, where `[gotify.vonarx.online]` is a character class that matches almost any origin.

# Coverage gaps

- **Only `kipp` reports node metrics.** Prometheus runs there and reaches node-exporter on `:9100` for its own node only; `up` is `0` for `tars`, `case` and `mother` across the whole TSDB, while all four pods are `Ready` with no restarts. Cross-node kubelet scrapes on `:10250` succeed, so the block is port-specific and belongs to the host firewall, which comes from nix-config. `TargetDown` is the symptom.
- **`NodeClockNotSynchronising` can only ever name `kipp`**, for the same reason — it is the one node whose `node_timex_sync_status` is collected, so the other three drift invisibly. Skew there also shifts rule evaluation, Prometheus and Alertmanager both sitting on that node.
- **kube-proxy has no pod to select.** k3s runs it inside the agent, so the chart's `k8s-app: kube-proxy` Service selector matches nothing and `KubeProxyDown`, an `absent()` rule, fires forever. `kubeProxy.endpoints` names the four node IPs to build the Endpoints by hand; it still needs `metrics-bind-address=0.0.0.0` on the agents from nix-config, and it inherits the firewall constraint above.

Grafana's **Alertmanager datasource has no backend**, so `/api/datasources/uid/alertmanager/health` answers `HTTP 500 plugin.unavailable` every time ([grafana#83794](https://github.com/grafana/grafana/issues/83794)). The datasource provisions and works in the browser; only the server-side health API is unimplemented for this type. A health sweep — `check_datasources_health` on the MCP server — therefore reports it broken on a healthy cluster. Not a fault to chase.

# Dashboards

Dashboards live with the app they describe, not with Grafana: a JSON file under the app's `files/`, turned into a ConfigMap by `#ConfigMapFiles` carrying `grafana_dashboard: "1"` plus `app.kubernetes.io/name` and `app.kubernetes.io/instance` labels. `cue/infrastructure/security/kanidm/files/kanidm-logs.json` is the worked example.

That is not just a convention — Grafana runs with no persistence, its `storage` volume an `emptyDir`, so `grafana.db` dies with the pod. Dashboards and datasources are re-provisioned at start-up and the admin user is re-created from the `grafana-admin` Secret, but everything else held in that database — service accounts and their tokens, silences, stars, preferences — is gone. A dashboard authored in the UI is a scratch buffer, not a change, and the read-only MCP server's service account has to be re-minted by hand after every restart — Grafana provisions no service accounts ([grafana#82987](https://github.com/grafana/grafana/issues/82987)), so `kube-prometheus-stack/grafana-service-account.txt` carries the procedure.
