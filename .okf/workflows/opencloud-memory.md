---
type: Reference
title: Diagnosing opencloud's memory
description: opencloud is one Go process for all its services, pprof is off, and a bleve merge that OOMs is self-perpetuating — what to measure and what the crashloop looks like.
tags: [opencloud, memory, oom, bleve, search, pprof]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-05T22:00:00Z }
---

# One process, one heap

Every opencloud service — proxy, search, storage-users, the embedded NATS — runs
in a single Go process in the `opencloud` container. A `"service"` field in a log
line names the subsystem, not a process. So the per-service debug endpoints all
report the _same_ whole-process runtime: `go_memstats_heap_inuse_bytes` on
`GRAPH_DEBUG_ADDR` (`:9124`) is the total heap, and nothing in-process attributes
it to a service.

`/debug/pprof` answers **404**. It is registered only when the owning service has
`<SERVICE>_DEBUG_PPROF=true`, which nothing sets here. Without it, memory work is
limited to the `/metrics` counters above plus `/proc/1/io` and `/proc/1/status`
read through `kubectl exec`. Reading `read_bytes`/`rchar` alongside RSS is what
separates "allocating from data already in memory" from "reading something large"
— a burst with flat IO counters is neither a big upload nor a segment being
loaded from disk.

# The bleve merge ceiling

The search index on [the data volume](/platform/storage.md) is scorch segments.
bleve merges them by building the merged segment **in heap and writing it at the
end**, so peak heap scales with the segments being merged, not with the steady
state — measured at 5.9GB against a ~400Mi idle heap and a ~1GB index.

An OOMKill during that merge is self-perpetuating: the merged segment is never
written, so the next start retries the same merge and dies at the same point.
The signature is a crashloop with **nothing in the logs at any level** — `info`
shows a normal startup and normal request handling right up to the kill. Confirm
it from `.status.containerStatuses[].lastState.terminated` (`reason: OOMKilled`,
`exitCode: 137`), not from log output. A new `.zap` file appearing in the store
is what tells you a merge finally completed.

Upstream has the related amplification bug, where extraction writes back metadata
that bumps parent mtimes and re-triggers indexing:
[opencloud#3589](https://github.com/opencloud-eu/opencloud/issues/3589).
`SEARCH_EXTRACTOR_TYPE=basic` (i.e. `tika.enabled: false`) is the escape hatch if
the ceiling stops holding; it costs content search and keeps filename search.
