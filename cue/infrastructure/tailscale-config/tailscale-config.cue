package tailscaleconfig

// cSpell:ignore tailscaleconfig

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#ConfigBundle & {
	needs: ["tailscale"]

	// ProxyGroup.status carries conditions, devices and url — no top-level
	// observedGeneration and no Reconciling/Stalled condition — so kstatus
	// assesses it by its generic fallback and the gate is weak rather than
	// absent. See /architecture/capability-graph.md.
	wait: true
	resources: [_proxyClass, _proxyGroup]
}

// The label the spread selects on is our own rather than one of the operator's:
// pod.labels merges with the labels the operator applies, so the constraint does
// not depend on an undocumented internal spelling.
let podLabel = {"vonarx.online/proxy-group": _proxyGroup.metadata.name}

// The operator applies neither affinity rules nor topology spread constraints of
// its own, so without this every replica may land on one node.
_proxyClass: {
	apiVersion: "tailscale.com/v1alpha1"
	kind:       "ProxyClass"
	metadata: name: "spread"
	spec: statefulSet: pod: {
		labels: podLabel & {"app.kubernetes.io/name": "tailscale"}
		// DoNotSchedule across the three schedulable nodes, which degrades to 2+1
		// during a drain where a required podAntiAffinity would leave a pod
		// Pending. nodeTaintsPolicy keeps the reserved node out of the skew.
		topologySpreadConstraints: [{
			maxSkew:           1
			topologyKey:       "kubernetes.io/hostname"
			whenUnsatisfiable: "DoNotSchedule"
			nodeTaintsPolicy:  "Honor"
			labelSelector: matchLabels: podLabel
		}]
	}
}

// The proxies every tailnet-exposed Ingress names through the
// tailscale.com/proxy-group annotation. Cluster-scoped, like the ProxyClass.
_proxyGroup: {
	apiVersion: "tailscale.com/v1alpha1"
	kind:       "ProxyGroup"
	// Named in schema so the ingresses' proxy-group annotation and this object
	// cannot drift apart.
	metadata: name: schema.#TailnetProxyGroup
	spec: {
		type:       "ingress"
		replicas:   3
		proxyClass: _proxyClass.metadata.name
	}
}
