---
type: Decision
title: Jellyfin is not scraped
description: Jellyfin's EnableMetrics is off because prometheus-net exposes 361 series of .NET runtime internals and nothing about playback, so the data does not answer any question asked of a media server.
tags: [jellyfin, prometheus, metrics, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-02T12:45:00Z }
stale_after: 2027-04-02
---

# Decision

`EnableMetrics` stays `false` in Jellyfin's `system.xml`, and no ServiceMonitor
exists for it. Its health is read from [the log pipeline](/platform/observability.md)
and from the pod's own cgroup via cAdvisor.

Tried and reverted: the setting on, a ServiceMonitor against the ClusterIP, and a
`replacePathRegex` middleware keeping `/metrics` off the public router.

# Why

What the endpoint serves is `prometheus-net`'s instrumentation of the host
process, not Jellyfin's instrumentation of itself — **there are no playback,
transcode, session or bandwidth metrics, because Jellyfin defines none.** The
questions worth asking about a media server are all answered elsewhere or not at
all.

Of 361 series, roughly 40 carry information:

| Group                                    | Series |                                                                                                                                                                     |
| ---------------------------------------- | -----: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `microsoft_aspnetcore_*`                 |    132 | duplicates `http_*`, and exposes cumulative values as **gauges**, so `rate()` over them is wrong                                                                    |
| `system_runtime_*` + `dotnet_*`          |     90 | two further overlapping views of the same GC, JIT and threadpool counters                                                                                           |
| `http_*`                                 |     42 | the part worth having — `http_request_duration_seconds` is labelled by route pattern, so cardinality stays bounded and unmatched requests collapse to `endpoint=""` |
| `system_net_*`                           |     35 | TLS broken out per version, all zero: Traefik terminates TLS and `EnableHttps` is false                                                                             |
| `private_internaldiagnostics_…_msquic_*` |     32 | QUIC internals, all zero, no HTTP/3 anywhere in the path                                                                                                            |
| `prometheus_net_*`                       |     15 | the exporter measuring itself                                                                                                                                       |
| `process_*`                              |      8 | **worse than cAdvisor** — scoped to the .NET process, so it excludes the ffmpeg children that do the expensive work                                                 |
| `microsoft_entityframeworkcore_*`        |      7 | query and savechanges counts, the only Jellyfin-specific signal present                                                                                             |

The request histogram and two gauges (`dotnet_threadpool_queue_length`,
`dotnet_gc_pause_ratio`, for threadpool starvation and GC thrash) are genuinely
unavailable elsewhere. They did not justify the retention cost, nor the ingress
machinery the endpoint drags with it: `/metrics` shares Jellyfin's only HTTP port,
so keeping it internal takes [a middleware on the public router](/platform/networking-and-ingress.md).

# What it costs

A latency regression in Jellyfin's own HTTP handling is invisible until it shows
up as a slow UI. Nothing watches .NET-level exhaustion, so threadpool starvation
would read as a generic hang.

Reversing is two edits — the setting, and a ServiceMonitor against the `http`
port at `/metrics`. Filter it on the way in if so: a keep-list for `http_*` plus
the two gauges is the version that was worth running.
