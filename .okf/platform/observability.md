---
type: Infrastructure
title: Observability
description: The metrics, logs and notification path — kube-prometheus-stack, Loki fed by Alloy, and Gotify running a repo-built image.
tags: [prometheus, grafana, loki, alloy, gotify, alerting]
resource: cue/infrastructure/observability
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T21:00:00Z }
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

The dev shell ships `grafana-alloy` so this file can be checked with `alloy fmt`/`alloy validate` before committing.

# Alerting path

Alertmanager → `gotify-alertmanager-bridge` (`ghcr.io/druggeri/alertmanager_gotify_bridge`) <!-- cSpell:ignore druggeri --> → Gotify.

Gotify itself runs `ghcr.io/joker9944/gotify-custom`, an image **built by this repo** so that the `gotify-slack-webhook` Go plugin is compiled against a matching gotify-server ABI. That constraint is the reason `pkgs/gomod-cap.nix` exists — see [images and CI](/workflows/images-and-ci.md). Gotify keeps state in its own CNPG cluster and uses `ghcr.io/joker9944/postgresql-client`, another repo-built image, as a helper container.

**v3 configures from the environment only, and a list value is one bare CSV line.** The v2 `[a,b]` form still parses — as a single element with the brackets in it. That is silent both ways: gin discards the error from `SetTrustedProxies`, so a bracketed CIDR just leaves `X-Forwarded-For` unread, and CORS origins are unanchored regexes, where `[gotify.vonarx.online]` is a character class that matches almost any origin.

# Dashboards

Dashboards live with the app they describe, not with Grafana: a JSON file under the app's `files/`, turned into a ConfigMap by `#ConfigMapFiles` carrying `grafana_dashboard: "1"` plus `app.kubernetes.io/name` and `app.kubernetes.io/instance` labels. `cue/infrastructure/security/kanidm/files/kanidm-logs.json` is the worked example.
