# Reference

Upstream behaviour this repo depends on but does not control, read off the pinned source rather than the vendor's prose.

**`sources` is mandatory here.** Nothing in this tree can be re-derived by reading the repo, so every concept must name what it was read from, pinned to the tag or commit that was current — never a moving branch. Attribute individual claims with `[^id]` footnotes joining to those entries.

- [kanidm OIDC clients and claims](oidc-claim-mapping.md) - how a client_id resolves, which claim carries which attribute, and what never leaves kanidm.
- [Prometheus metric labels in Kubernetes](prometheus-metric-labels.md) - what `job` and `instance` mean, which labels a Kubernetes target carries, and how a label collision is resolved.
- [Loki stream labels and how Alloy sets them](loki-stream-labels.md) - what a label costs, when a value belongs in structured metadata or a filter expression, and which Alloy construct sets each.
