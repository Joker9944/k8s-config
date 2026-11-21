// The capability graph as a Mermaid flowchart, one subgraph per tier, each edge
// labelled with the capability that put it there. Built from the same `edges`
// #Tier.sync renders into dependsOn, and spliced into
// .okf/architecture/capability-graph.md by the capability-graph pre-commit hook.
//
//   cue export ./graph -e doc --out text

package graph

import (
	"list"
	"strings"

	cloud "github.com/joker9944/k8s-config/apps/cloud:tier"
	games "github.com/joker9944/k8s-config/apps/games:tier"
	media "github.com/joker9944/k8s-config/apps/media:tier"
	controllers "github.com/joker9944/k8s-config/infrastructure/controllers:tier"
	observability "github.com/joker9944/k8s-config/infrastructure/observability:tier"
	plugins "github.com/joker9944/k8s-config/infrastructure/plugins:tier"
	security "github.com/joker9944/k8s-config/infrastructure/security:tier"
	storage "github.com/joker9944/k8s-config/infrastructure/storage:tier"
)

_tiers: [
	controllers.tier,
	plugins.tier,
	storage.tier,
	security.tier,
	observability.tier,
	cloud.tier,
	games.tier,
	media.tier,
]

// Mermaid reads `-` in a bare id as the start of a link.
#Id: {
	in:  string
	out: strings.Replace(in, "-", "_", -1)
}

_nodes: [for t in _tiers {
	tier: t
	names: list.SortStrings([for n, _ in t.bundles {n}])
}]

// A provider needing its own capability is filtered, as in #Tier.sync.
_edges: list.SortStrings([
	for t in _tiers
	for k, b in t.bundles
	for p, c in b.edgeCapabilities if p != k {
		"  \((#Id & {in: k}).out) -->|\(c)| \((#Id & {in: p}).out)"
	},
])

_lines: list.Concat([
	["flowchart BT"],
	[for n in _nodes for l in list.Concat([
		["  subgraph tier_\(n.tier.name)[\"\(n.tier.tree)/\(n.tier.name)\"]"],
		[for b in n.names {"    \((#Id & {in: b}).out)[\"\(b)\"]"}],
		["  end"],
	]) {l}],
	_edges,
])

_bundles: list.Sum([for n in _nodes {len(n.names)}])

doc: """
	\(_bundles) bundles, \(len(_edges)) edges.

	```mermaid
	\(strings.Join(_lines, "\n"))
	```

	"""
