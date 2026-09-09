---
type: Infrastructure
title: Observability
description: The metrics, logs and notification path — kube-prometheus-stack, Loki fed by Alloy, and Gotify running a repo-built image.
tags: [prometheus, grafana, loki, alloy, gotify, alerting]
resource: cue/infrastructure/observability
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-09T22:00:00Z }
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

The bridge chooses its Gotify application from a `?token=` on the webhook URL, so the receiver's URL is a credential and is not written in the release. It sets `url_file` instead, against a SOPS Secret named in `alertmanagerSpec.secrets`, which the operator mounts at `/etc/alertmanager/secrets/<name>/`. prometheus-operator re-marshals the raw config through its own structs and silently drops what it does not model: it does model `url_file`, but strips it below Alertmanager 0.26.0 and discards it outright when `url` is set alongside. Alertmanager reads the file inside each notification rather than at config load, so rotating the Secret needs no restart. The bridge's own `GOTIFY_TOKEN` is only the fallback for a request that carries no `?token=`; it holds a literal placeholder because the bridge exits 1 when it is unset, not because anything reads it.

Gotify itself runs `ghcr.io/joker9944/gotify-custom`, an image **built by this repo** so that the `gotify-slack-webhook` Go plugin is compiled against a matching gotify-server ABI. That constraint is the reason `pkgs/gomod-cap.nix` exists — see [images and CI](/workflows/images-and-ci.md). Gotify keeps state in its own CNPG cluster and uses `ghcr.io/joker9944/postgresql-client`, another repo-built image, as a helper container.

**v3 configures from the environment only, and a list value is one bare CSV line.** The v2 `[a,b]` form still parses — as a single element with the brackets in it. That is silent both ways: gin discards the error from `SetTrustedProxies`, so a bracketed CIDR just leaves `X-Forwarded-For` unread, and CORS origins are unanchored regexes, where `[gotify.vonarx.online]` is a character class that matches almost any origin.

# Dashboards

Dashboards live with the app they describe, not with Grafana: a JSON file under the app's `files/`, turned into a ConfigMap by `#ConfigMapFiles` carrying `grafana_dashboard: "1"` plus `app.kubernetes.io/name` and `app.kubernetes.io/instance` labels. `cue/infrastructure/security/kanidm/files/kanidm-logs.json` is the worked example.
