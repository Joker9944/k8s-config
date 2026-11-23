// The capability graph as a Mermaid flowchart, one subgraph per tree, each edge
// labelled with the capability that put it there. Built from the same `edges`
// #Manifests.sync renders into dependsOn, and spliced into
// .okf/architecture/capability-graph.md by the capability-graph pre-commit hook.
//
//   cue export ./graph -e doc --out text

package graph

import (
	"list"
	"strings"

	"github.com/joker9944/k8s-config/manifests"
)

_trees: [
	{name: "infrastructure", bundles: manifests.infrastructure},
	{name: "apps", bundles: manifests.apps},
]

// Mermaid reads `-` in a bare id as the start of a link.
#Id: {
	in:  string
	out: strings.Replace(in, "-", "_", -1)
}

_nodes: [for t in _trees {
	tree: t.name
	names: list.SortStrings([for n, _ in t.bundles {n}])
}]

// A provider needing its own capability is filtered, as in #Manifests.sync.
_edges: list.SortStrings([
	for k, b in manifests.manifests.bundles
	for p, c in b.edgeCapabilities if p != k {
		"  \((#Id & {in: k}).out) -->|\(c)| \((#Id & {in: p}).out)"
	},
])

_lines: list.Concat([
	["flowchart BT"],
	[for n in _nodes for l in list.Concat([
		["  subgraph \(n.tree)"],
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
