---
type: Convention
title: Telemetry label convention
description: The label set every log stream and metric series should carry, why `cluster` is an anchor rather than an identity, why `service_name` needs no rule of its own, and why the two signals do not spell the service the same way.
tags: [prometheus, loki, alloy, labels, logs, metrics]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-28T00:00:00Z }
---

The label set to aim at. What the pipeline emits today is
[observability](/platform/observability.md); what a label costs is upstream
behaviour, in [Loki stream labels](/reference/loki-stream-labels.md) and
[Prometheus metric labels](/reference/prometheus-metric-labels.md). Neither the
sourcing rules nor the gap between this set and the current one belong here —
the `label-conformance` dashboard reports that gap.

# Logs

Five indexed stream labels:

| label       | carries                                     |
| ----------- | ------------------------------------------- |
| `cluster`   | the cluster, as the universal anchor        |
| `namespace` | the workload's namespace                    |
| `app`       | the workload, from `app.kubernetes.io/name` |
| `container` | the container within the pod                |
| `job`       | `<namespace>/<container>`                   |

**`service_name` needs no rule of its own.** `discover_service_name` is narrowed
to `app`, so Loki writes `service_name` from it and `unknown_service` means
exactly "missing `app`" — in Drilldown, in the label API and in a selector alike.

That is also why `app` must never be given a fallback that invents a plausible
value: it would leave `{app=""}` permanently empty, with nothing left to measure.
A source that cannot supply `app` has to arrive unset.

**Two log sources are exempt.** `loki-canary` pushes to Loki directly rather than
through Alloy and carries only `pod` and `stream`, so it satisfies none of this
and is invisible to a `cluster`-anchored query besides. The cluster-events source
is not a pod stream and has no container to name. Neither is a workload, and
neither is a defect to chase.

# `cluster` is an anchor, not an identity

Its cardinality is 1 and it will stay 1 — nothing here will ever monitor a second
cluster. It is kept anyway because **a Loki selector needs at least one non-empty
matcher**, so expressing "every stream" requires one label that every stream can
carry, and no other candidate qualifies: `job` and `container` are absent on
anything that pushes to Loki directly rather than through Alloy, `namespace` is
absent on sources that are not a pod.

That makes it the one place a constant-valued label is correct. The cost
upstream warns about is stream count, and a label with one value splits nothing —
it spends one of the fifteen `max_label_names_per_series` slots and fragments no
chunks. The same reasoning does not transfer to any other label: a second
constant would cost a slot and buy nothing, because the anchor already exists.

# Metrics

Five target labels on every scrape, which prometheus-operator emits for any
Kubernetes target:

| label       | carries                                              |
| ----------- | ---------------------------------------------------- |
| `job`       | the target's purpose, asserted by the ServiceMonitor |
| `instance`  | the scraped endpoint, `<host>:<port>`                |
| `namespace` | the Service's namespace                              |
| `service`   | the Service object's name                            |
| `endpoint`  | the port's name, or its number if unnamed            |

Three more where the target is a workload pod, and only there:

| label       | carries                         |
| ----------- | ------------------------------- |
| `pod`       | the pod backing the endpoint    |
| `container` | the container exposing the port |
| `node`      | the node the pod runs on        |

**The control-plane targets carry none of the second group.** `kubelet`,
`apiserver` and `kube-proxy` are scraped through Endpoints that address nodes and
control-plane members rather than pods, so there is no pod to name; `node`
narrows further still and reaches only `kubelet`. Requiring the second group
everywhere would make a permanent false positive out of a target that is
behaving correctly.

**`cluster` is deliberately absent here.** `{__name__!=""}` selects every series,
so the anchor problem the log side has does not exist, and matching the log side
for its own sake is not a reason. A mixin dashboard templating `$cluster`
degrades to an empty matcher, which matches series that lack the label.

# The service is spelled differently per signal, and `job` is not a join key

`service_name` on logs and `job` on metrics are the same concept wearing the
spelling each backend made canonical, and the divergence is upstream's, not a
local inconsistency to fix. The OpenTelemetry mapping into Prometheus folds
`service.namespace` and `service.name` into **`job`** and `service.instance.id`
into `instance`, rather than emitting a `service_name` label at all; Loki, Tempo
and Pyroscope index it as `service_name`. Writing `service_name` onto metrics
would also collide: kube-state-metrics already uses that name for the name of a
Kubernetes `Service` object, which is a different thing entirely.

So `job` is **not** a cross-signal join key. It means `<namespace>/<container>` on
a log stream and whatever the ServiceMonitor asserts on a series. `namespace`
plus the workload is the correspondence that holds across both.

# What stays out of the index

`pod`, `node`, `component` and `version` belong in structured metadata, and
`instance` has no place on a log stream at all — it is a concatenation of values
already present. Structured metadata keeps them queryable after the selector
without creating a stream per value, which is what an identifier that changes on
every restart or every image bump would otherwise do.

**Demotion is not admission.** A value earns a place in structured metadata only
if something cannot reach it otherwise: it is absent from the stored line, or it
has a named consumer that reads fields rather than lines. Anything still in the
line is a filter expression's job — Loki's own default, and free. Getting this
wrong is invisible to the `label-conformance` dashboard and will stay that way:
structured metadata is not an index label, cannot appear in a stream selector,
and the label API does not list it, so no panel can enumerate what a pipeline
attaches. It is not free for being index-free either — it is extracted onto every
returned line, so a metric query over a stream carrying a lot of it can exhaust
its series budget.

`env` and `container_runtime` are excluded outright rather than demoted: there is
one environment and one container runtime (`containerd`), so neither would carry
information in either place. `container_runtime` is the second constant the
anchor above rules out — it spends one of the fifteen slots and buys nothing.
