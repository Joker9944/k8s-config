---
type: Reference
title: Prometheus metric labels in Kubernetes
description: What job and instance mean, which labels a Kubernetes target carries and where each one comes from, how a collision between exposed and server-side labels is resolved, and what makes a label value safe to add.
tags:
  [prometheus, labels, metrics, cardinality, relabeling, prometheus-operator]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-17T00:00:00Z }
sources:
  - id: prom-jobs-instances
    resource: https://github.com/prometheus/docs/blob/8bdb919e820ad27adc12fc66daf38531c3d9a801/docs/concepts/jobs_instances.md
    title: Prometheus docs — Jobs and instances
    last_modified: 2025-05-28
  - id: prom-data-model
    resource: https://github.com/prometheus/docs/blob/8bdb919e820ad27adc12fc66daf38531c3d9a801/docs/concepts/data_model.md
    title: Prometheus docs — Data model
    last_modified: 2025-05-28
  - id: prom-metric-types
    resource: https://github.com/prometheus/docs/blob/4933d0570cfd4cb44f1686cf63df5c0482594349/docs/concepts/metric_types.md
    title: Prometheus docs — Metric types
    last_modified: 2026-03-10
  - id: prom-naming
    resource: https://github.com/prometheus/docs/blob/410443d27be8bc911af86a826beb13c25d46e4dd/docs/practices/naming.md
    title: Prometheus docs — Metric and label naming
    last_modified: 2026-01-27
  - id: prom-scrape-config
    resource: https://github.com/prometheus/prometheus/blob/v3.15.0/docs/configuration/configuration.md
    title: Prometheus 3.15.0 — configuration reference
  - id: operator-api
    resource: https://github.com/prometheus-operator/prometheus-operator/blob/v0.94.1/Documentation/api-reference/api.md
    title: prometheus-operator 0.94.1 — API reference
  - id: operator-promcfg
    resource: https://github.com/prometheus-operator/prometheus-operator/blob/v0.94.1/pkg/prometheus/promcfg.go
    title: prometheus-operator 0.94.1 — pkg/prometheus/promcfg.go
  - id: cncf-labels
    resource: https://www.cncf.io/blog/2025/07/22/prometheus-labels-understanding-and-best-practices/
    title: CNCF — Prometheus labels, understanding and best practices
    last_modified: 2025-07-22
---

Upstream behaviour, read against Prometheus 3.15.0 and prometheus-operator 0.94.1. Nothing here describes this
repo's configuration — see [observability](/platform/observability.md) for what the cluster actually does, and note
that the log pipeline's conventions are [a different scheme with different costs](/reference/loki-stream-labels.md).

# A job is a purpose, an instance is a process

An **instance** is one scrapeable endpoint, usually one process; a **job** is the set of instances that share a
purpose — replicas of the same thing.[^prom-jobs-instances] Prometheus attaches both to every sample it ingests:
`job` from the scrape configuration, `instance` from the `<host>:<port>` of the URL scraped.[^prom-jobs-instances]

Neither is discovered. `job` is asserted by whoever wrote the scrape config, which makes it the only label that
carries intent rather than topology — two endpoints land in one job because a human said they serve the same
purpose, and nothing validates that claim. A single process exposing several ports, or several registries, is
therefore as free to appear as three jobs as three replicas are to appear as one.

Five series are synthesised per scrape and are not part of the target's exposition: `up` (1 on a successful
scrape), `scrape_duration_seconds`, `scrape_samples_scraped`, `scrape_samples_post_metric_relabeling` and
`scrape_series_added`.[^prom-jobs-instances] `up` is the availability signal — a target that stops existing stops
producing it rather than reporting 0.

# Where a Kubernetes target's labels come from

Service discovery contributes `__meta_*` labels that vary per mechanism; the Kubernetes mechanism exposes object
metadata that way — `__meta_kubernetes_pod_name`, `__meta_kubernetes_service_label_<name>` and so on. **Every label
starting with `__` is removed once target relabeling finishes**,[^prom-scrape-config] so a `__meta_*` value only
reaches storage if a relabel rule copied it to a real name. `__tmp` is the one prefix Prometheus guarantees it will
never use itself, for values a later rule consumes.[^prom-scrape-config]

`instance` defaults to `__address__` only if relabeling left it unset,[^prom-scrape-config] and `__address__` is
the target's `<host>:<port>` — for pod discovery that is the pod IP, which is a new value after every restart. The
`node` role is the exception worth knowing: there `instance` is set to the node name from the API
server.[^prom-scrape-config] So `instance` identifies a process for node-level exporters and identifies nothing
durable for a workload pod; group a workload by `pod`, `service` or `job` and reach for `instance` only to
distinguish replicas within one query.

**prometheus-operator writes that relabeling for you**, and the two monitor kinds are not
symmetric:[^operator-api]

|                            | ServiceMonitor                                    | PodMonitor                             |
| -------------------------- | ------------------------------------------------- | -------------------------------------- |
| `jobLabel` reads           | a label on the **Service** object                 | a label on the **Pod** object          |
| `job` when unset or absent | the **Service name**                              | `<namespace>/<name>` of the PodMonitor |
| object labels copied by    | `targetLabels` (Service), `podTargetLabels` (Pod) | `podTargetLabels`                      |

So a ServiceMonitor's `job` silently tracks the Service name — rename the Service and
every query, recording rule and dashboard grouping on `job` breaks — while a PodMonitor's tracks the monitor's own
name. Setting `jobLabel` to a label the object actually carries is what decouples `job` from either name. The operator also
emits relabelings for standard Kubernetes fields unasked, so `namespace`, `service`, `pod`, `container` and `node`
are always present — and `endpoint`, which is the **port's name**, falling back to the port number for an unnamed
port.[^operator-promcfg]

# Two relabel phases, two purposes

`relabelings` rewrites a **target** before it is scraped and can drop it outright, so it decides _what gets
scraped_ and _what the target's labels are_.[^prom-scrape-config] `metricRelabelings` runs on **samples** as the
last step before ingestion, with the same actions, and is where a series is dropped for being too expensive to
store.[^prom-scrape-config] Two consequences follow from the ordering: a target dropped in the first phase costs
nothing, whereas a series dropped in the second was still scraped and transferred; and **metric relabeling does not
apply to the synthesised series**,[^prom-scrape-config] so `up` survives any `drop` rule written against it.

# Collisions: `honor_labels` and the `exported_` prefix

When scraped data already carries a label Prometheus would attach server-side — `job`, `instance`, a configured
target label, or anything service discovery produced — `honor_labels` decides who wins. At its default of `false`
the **exposed** label is renamed to `exported_<name>` and the server-side value takes the plain name; at `true` the
exposed value is kept and the server-side one is discarded.[^prom-scrape-config]

That default makes an `exported_namespace` or `exported_job` in storage a signal, not a fault: the target is
exposing a label the scrape also sets. It is correct for an exporter that reports on itself and wrong for one
reporting on something else — federation and Pushgateway are the cases `honor_labels: true`
exists for.[^prom-scrape-config] The operator surfaces this as `honorLabels` per monitor, and
`overrideHonorLabels` on the Prometheus object forces `honorLabels: false` across every ServiceMonitor, PodMonitor
and ScrapeConfig.[^operator-api] `external_labels` is unaffected by the setting either way.[^prom-scrape-config]

An application should therefore not expose `job`, `instance`, `namespace` or `pod` itself. The scrape supplies all
four, and exposing them produces a doubled label set rather than an error.

# What makes a label value safe

A label differentiates characteristics of the thing measured — `operation="create|update|delete"`,
`stage="extract|transform|load"`.[^prom-naming] Every distinct key-value combination is a separate time series, so
a label whose value set is unbounded multiplies storage without bound: user IDs, email addresses "or other
unbounded sets of values" are the documented anti-examples,[^prom-naming] and request IDs, UUIDs, raw query text,
IP addresses and timestamps are the same mistake.[^cncf-labels] The practical test is whether you can enumerate the
values in advance; if not, the dimension belongs in a log line or a trace, not a label.

Mechanics that bite:

- **An empty label value is equivalent to the label not existing.**[^prom-data-model] A relabel rule or template
  that writes `""` on a miss does not create a distinguishing series — but it also does not fail, so the mistake is
  silent in the other direction: a rule that stamps an empty value on every sample looks like it did nothing.
- **`le` and `quantile` are taken.** Classic histogram buckets are `<basename>_bucket{le="<upper bound>"}` and
  summaries are `<basename>{quantile="<φ>"}`; since Prometheus 3.0 both values are normalised at
  ingestion.[^prom-metric-types] Reusing either name for anything else collides with `histogram_quantile`.
- **`__` is reserved for internal use**, label names should match `[a-zA-Z_][a-zA-Z0-9_]*`, and although Prometheus
  3 accepts any UTF-8 in names and values, anything outside that set needs quoting in PromQL and is not yet safely
  portable across the ecosystem.[^prom-data-model]
- **Do not repeat a label's name inside the metric name** — it is redundant, and misleading once that label is
  aggregated away.[^prom-naming]

# Labels are part of a metric's identity

Changing any label value, **including adding or removing a label**, creates a new time series.[^prom-data-model]
There is no migration: existing queries, recording rules, alert expressions and dashboard groupings keep matching
the old series until it goes stale, and a `sum by (…)` naming a label that no longer exists silently collapses to
one group instead of erroring. A label added to a metric that already has history is a schema change, which is the
argument for deciding the label set before instrumenting rather than growing it per
question.[^cncf-labels]

[^prom-jobs-instances]: [Jobs and instances](https://github.com/prometheus/docs/blob/8bdb919e820ad27adc12fc66daf38531c3d9a801/docs/concepts/jobs_instances.md)

[^prom-data-model]: [Data model](https://github.com/prometheus/docs/blob/8bdb919e820ad27adc12fc66daf38531c3d9a801/docs/concepts/data_model.md)

[^prom-metric-types]: [Metric types](https://github.com/prometheus/docs/blob/4933d0570cfd4cb44f1686cf63df5c0482594349/docs/concepts/metric_types.md)

[^prom-naming]: [Metric and label naming](https://github.com/prometheus/docs/blob/410443d27be8bc911af86a826beb13c25d46e4dd/docs/practices/naming.md)

[^prom-scrape-config]: [Prometheus 3.15.0 configuration reference](https://github.com/prometheus/prometheus/blob/v3.15.0/docs/configuration/configuration.md) — `<scrape_config>`, `<relabel_config>`, `<metric_relabel_configs>`, `kubernetes_sd_config`

[^operator-api]: [prometheus-operator 0.94.1 API reference](https://github.com/prometheus-operator/prometheus-operator/blob/v0.94.1/Documentation/api-reference/api.md) — `ServiceMonitorSpec`, `PodMonitorSpec`, `Endpoint`, `CommonPrometheusFields`

[^operator-promcfg]: [prometheus-operator 0.94.1 — `pkg/prometheus/promcfg.go`](https://github.com/prometheus-operator/prometheus-operator/blob/v0.94.1/pkg/prometheus/promcfg.go) — the generated `relabel_configs`

[^cncf-labels]: [CNCF — Prometheus labels, understanding and best practices](https://www.cncf.io/blog/2025/07/22/prometheus-labels-understanding-and-best-practices/)
