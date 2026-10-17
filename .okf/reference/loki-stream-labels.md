---
type: Reference
title: Loki stream labels and how Alloy sets them
description: What a Loki label costs, the limits that make the label advice enforceable, when a value belongs in structured metadata or a filter expression instead, how `service_name` resolves itself, and which Alloy construct sets each kind.
tags: [loki, alloy, labels, logs, cardinality, structured-metadata]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-17T00:00:00Z }
sources:
  - id: loki-labels
    resource: https://github.com/grafana/loki/blob/v3.7.8/docs/sources/get-started/labels/_index.md
    title: Loki 3.7.8 — Understand labels
    last_modified: 2026-06-25
  - id: loki-bp-labels
    resource: https://github.com/grafana/loki/blob/v3.7.8/docs/sources/get-started/labels/bp-labels.md
    title: Loki 3.7.8 — Label best practices
    last_modified: 2026-03-26
  - id: loki-structured-metadata
    resource: https://github.com/grafana/loki/blob/v3.7.8/docs/sources/get-started/labels/structured-metadata.md
    title: Loki 3.7.8 — Structured metadata
    last_modified: 2026-08-19
  - id: loki-config
    resource: https://github.com/grafana/loki/blob/v3.7.8/docs/sources/shared/configuration.md
    title: Loki 3.7.8 — configuration reference, `limits_config`
    last_modified: 2026-08-27
  - id: alloy-loki-process
    resource: https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/loki/loki.process.md
    title: Alloy v1.20.1 — `loki.process`
    last_modified: 2026-08-24
  - id: alloy-loki-relabel
    resource: https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/loki/loki.relabel.md
    title: Alloy v1.20.1 — `loki.relabel`
    last_modified: 2026-03-31
  - id: alloy-discovery-relabel
    resource: https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/discovery/discovery.relabel.md
    title: Alloy v1.20.1 — `discovery.relabel`
    last_modified: 2026-03-31
  - id: alloy-loki-source-file
    resource: https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/loki/loki.source.file.md
    title: Alloy v1.20.1 — `loki.source.file`
    last_modified: 2026-03-31
---

Upstream behaviour, read against Loki 3.7.8 and Alloy v1.20.1. Nothing here describes this repo's pipeline — see
[observability](/platform/observability.md) for what the cluster actually ships, and
[Prometheus metric labels](/reference/prometheus-metric-labels.md) for the metrics side, which is a different
scheme with different costs.

# A stream is a label set

Loki does not index log content. Entries are grouped into **streams**, one per exact set of label key-value pairs,
and only those label sets are indexed; a query selects streams and then iterates their
entries.[^loki-labels] Changing one label value creates a new stream.[^loki-labels]

Names follow Prometheus's rules — `[a-zA-Z_:][a-zA-Z0-9_:]*`, unsupported characters converted to underscores, so
`app.kubernetes.io/name` becomes `app_kubernetes_io_name`. Names wrapped in double underscores are reserved for
internal labels such as `__stream_shard__`, which the label browser, query builder and autocomplete all
hide.[^loki-labels]

Because a stream is the unit of storage, two costs follow from the same choice. A label with many values means a
large index; it also means the lines are spread over more, smaller chunks. Upstream names both — high cardinality
makes Loki "build a huge index and flush thousands of tiny chunks to the object store" — and it names the second
cause explicitly: **too many labels does this even when every one of them is bounded**.[^loki-labels]

# The limits that make the advice enforceable

The "aim for 10–15 labels" guidance[^loki-labels] is not only style. `limits_config` defaults:[^loki-config]

| limit                                   | default       |
| --------------------------------------- | ------------- |
| `max_label_names_per_series`            | 15            |
| `max_label_name_length`                 | 1024          |
| `max_label_value_length`                | 2048          |
| `allow_structured_metadata`             | `true`        |
| `max_structured_metadata_size`          | 64KB per line |
| `max_structured_metadata_entries_count` | 128 per line  |

A sixteenth label is a rejection, not a slow query. Structured metadata is bounded too, and the failure mode is
worth knowing before it happens: a line over either limit is rejected by the distributor with **HTTP 400** and
counted in `loki_discarded_samples_total` under reason `structured_metadata_too_large` or
`structured_metadata_too_many` — a stack trace attached as an attribute is the documented
cause.[^loki-structured-metadata]

For scale, upstream's own ceiling is **under 100,000 active streams per tenant** and under a million in 24 hours,
and it frames those as numbers for a tenant sending more than 10 TB a day: a tenant 10× smaller should have at
least 10× fewer labels.[^loki-bp-labels]

# Label, structured metadata, or filter expression

Three places a value can go, and the default is the last one.

**Static labels are the good case** — region, cluster, host, application, namespace, environment: fixed for a
given system and bounded.[^loki-bp-labels] A bounded-but-large static set is fine; 1,000 hosts in a `host` label is
explicitly called out as acceptable.[^loki-bp-labels]

**A filter expression is the default for anything in the line.** Loki does not need a label to search a field —
`|=`, `|~`, `!=` iterate the stream in parallel, and the rule is "don't add a label for something until you know
you need it".[^loki-bp-labels] Upstream's own worked retraction is `level`: `{app="loki"} |= "level=error"` proved
as fast as `{app="loki",level="error"}` for medium-to-low-volume apps, because the label splits one app into up to
five streams and so five times the chunks. A **negated** matcher is strictly worse —
`{app="loki",level!="debug"}` loads far more chunks than `{app="loki"} != "level=debug"`.[^loki-bp-labels] Log
level, log message and exception name are named as things not to label.[^loki-labels]

**Structured metadata is for high-cardinality values worth attaching anyway**, and upstream's framing is
restrictive — "you should only use structured metadata in the following situations": OpenTelemetry ingestion, a
high-cardinality value that is _not already in the line_ (process or thread ID, pod name), or Logs
Drilldown.[^loki-structured-metadata] It is attached in the push payload, costs no index and creates no stream, but
it is not a label: it is queried with a label-filter expression after the selector (`{job="x"} | pod="…"`), not in
the selector. And because it is extracted onto every returned line automatically, a metric query over a stream
carrying a lot of it can hit `maximum of series (50000) reached for a single query` — `keep` / `drop` is the
fix.[^loki-structured-metadata]

If a dynamic label is unavoidable: tens of values at most and ideally single digits, values that are long-lived
rather than ephemeral (the first segment of an HTTP path, not a trace or order ID), and only labels users will
actually query — an unused label costs index size and stream fragmentation for nothing.[^loki-bp-labels]
`logcli series --analyze-labels` prints unique values per label name against stream count, which is how the
diagnosis gets made rather than guessed; upstream's canonical bad case is a `requestId` with 24,653 values across
24,979 streams.[^loki-bp-labels]

# Why the cost shows up as chunk flushing

`chunk_target_size` cuts a chunk at a compressed size (1MB is reasonable, roughly 5MB of uncompressed logs), and
what you want to avoid is splitting a log file into streams whose chunks get flushed **because the stream went idle
or hit max age rather than because it filled**.[^loki-bp-labels] `sum by (reason)
(rate(loki_ingester_chunks_flushed_total[1m]))` is the metric that reports which.[^loki-bp-labels] The inverse is
the one volume-driven argument for a dynamic label: a stream writing a chunk's worth faster than `max_chunk_age`,
or many chunks in that window, is a candidate for splitting.[^loki-bp-labels]

# Ordering is per stream

Entries within one stream must be ingested in order, inside a two-hour window; older entries for that stream are
rejected with `too far behind`.[^loki-labels] Out-of-order writes are enabled globally by default. This is the
second case where adding a label is correct: a slow producer and a fast producer sharing
`{environment="production"}` interfere, and splitting them with an `app` label lets each keep its own
order.[^loki-labels]

# `service_name` is set for you, and it is a real label

Every stream gets a `service_name` index label whether or not the client sent one — it is part of the stream's
label set and selectable as `{service_name="…"}`. Loki keeps the client's value if there is one; otherwise it takes
**the first non-empty value in this order**, falling back to `unknown_service`:[^loki-labels]

```
service  app  application  app_name  name  app_kubernetes_io_name
container  container_name  k8s_container_name  component  workload  job  k8s_job_name
```

The order is the thing to notice, because a Kubernetes pipeline usually sets several of those. `container` sits
seventh and `job` twelfth, so a stream carrying both gets its `service_name` from the **container name** — a
pipeline's own `job` convention never reaches `service_name` unless nothing earlier in the list is present.
`app_kubernetes_io_name` outranks both, which is how a workload makes the choice deliberate rather than incidental.

It is worth getting right rather than ignoring: `service_name` is what Logs Drilldown and Grafana Cloud
Application Observability use to find and group logs, so a stream that falls through lands in those views as
`unknown_service` rather than under its own name.[^loki-labels] The list is the `discover_service_name` limit and an empty list disables the
behaviour entirely.[^loki-labels]

Its sibling `discover_log_levels` writes a level into structured metadata rather than a label; those mechanics and
the lowercase requirement are in [observability](/platform/observability.md).

# Which Alloy construct sets what

Three stages, and only the last one reads the line:[^alloy-loki-relabel]

| construct           | operates on                                           | use for                                                                          |
| ------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------- |
| `discovery.relabel` | a **target's** label set, before collection           | shaping `__meta_*` into real label names[^alloy-discovery-relabel]               |
| `loki.relabel`      | a **log entry's** label set, without reading the line | standardizing or filtering the label set between components[^alloy-loki-relabel] |
| `loki.process`      | the **line**                                          | everything that needs parsing[^alloy-loki-process]                               |

Two drop rules sit in there. `loki.relabel` **drops the entry entirely if no label survives** its
rules;[^alloy-loki-relabel] and target labels starting with `__` are internal — `loki.source.file` promotes
`__path__` to the `filename` label and every other double-underscore label is removed before downstream `loki.*`
components see it,[^alloy-loki-source-file] so a discovery value has to be mapped to a real name (a `labelmap`
stripping the prefix, or a rename) to survive.[^alloy-discovery-relabel]

Inside `loki.process`, the label-shaping stages are:[^alloy-loki-process]

- `stage.static_labels` — a fixed map, for labels that do not depend on the line.
- `stage.labels` — from the extracted-values map, or from structured metadata with
  `source_type = "structured_metadata"`. An empty value means "same key as the label".
- `stage.structured_metadata` — from the extracted map, by name or by `regex`. Documented as removing what it
  attaches from the label map, so it is a move rather than a copy.
- `stage.label_drop`, `stage.label_keep`, `stage.structured_metadata_drop` — subtractive, for narrowing a label
  set an upstream component produced.

[^loki-labels]: [Loki 3.7.8 — Understand labels](https://github.com/grafana/loki/blob/v3.7.8/docs/sources/get-started/labels/_index.md)

[^loki-bp-labels]: [Loki 3.7.8 — Label best practices](https://github.com/grafana/loki/blob/v3.7.8/docs/sources/get-started/labels/bp-labels.md)

[^loki-structured-metadata]: [Loki 3.7.8 — Structured metadata](https://github.com/grafana/loki/blob/v3.7.8/docs/sources/get-started/labels/structured-metadata.md)

[^loki-config]: [Loki 3.7.8 — configuration reference](https://github.com/grafana/loki/blob/v3.7.8/docs/sources/shared/configuration.md) — `limits_config`

[^alloy-loki-process]: [Alloy v1.20.1 — `loki.process`](https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/loki/loki.process.md)

[^alloy-loki-relabel]: [Alloy v1.20.1 — `loki.relabel`](https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/loki/loki.relabel.md)

[^alloy-discovery-relabel]: [Alloy v1.20.1 — `discovery.relabel`](https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/discovery/discovery.relabel.md)

[^alloy-loki-source-file]: [Alloy v1.20.1 — `loki.source.file`](https://github.com/grafana/alloy/blob/v1.20.1/docs/sources/reference/components/loki/loki.source.file.md)
