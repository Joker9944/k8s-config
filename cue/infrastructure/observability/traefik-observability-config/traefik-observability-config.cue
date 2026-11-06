package traefikobservabilityconfig

import "github.com/joker9944/k8s-config/schema"

// Traefik's monitor, in a bundle of its own because it cannot live with
// traefik: a bundle emitting a ServiceMonitor needs the `monitoring`
// capability, and traefik is what kube-prometheus-stack already reaches
// through `ingress`, so that edge would close a cycle. See
// /architecture/capability-graph.md. A config bundle on the far side of the
// edge has the CRD available and closes nothing.
//
// The object lands in the kube-prometheus-stack namespace, the one this
// bundle's single capability guarantees exists; a ServiceMonitor selects
// across namespaces, so that costs only a `namespaceSelector`.
bundle: schema.#ConfigBundle & {
	needs: ["monitoring"]
	resources: [_monitor]
}

// Traefik serves /metrics on the metrics entrypoint by chart default; its
// bundle adds only the ClusterIP this selects, and leaves the chart's own
// `metrics.prometheus.serviceMonitor` off.
_monitor: {
	apiVersion: "monitoring.coreos.com/v1"
	kind:       "ServiceMonitor"
	metadata: {
		name:      "traefik"
		namespace: "kube-prometheus-stack"
	}
	spec: {
		namespaceSelector: matchNames: ["traefik-system"]
		selector: matchLabels: {
			"app.kubernetes.io/name":      "traefik"
			"app.kubernetes.io/component": "metrics"
		}
		endpoints: [{
			port: "metrics"

			// Traefik labels its backends `service`, which is also the target
			// label carrying the Service object's name, so the scrape renames the
			// exposed one to `exported_service`. honorLabels would resolve the
			// collision the other way and cost the target label the convention
			// wants, so the exposed one is given a name of its own instead.
			metricRelabelings: [
				{sourceLabels: ["exported_service"], targetLabel: "backend"},
				{action: "labeldrop", regex: "exported_service"},
			]
		}]
	}
}
