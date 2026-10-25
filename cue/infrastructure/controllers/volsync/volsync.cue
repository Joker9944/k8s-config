package volsync

import (
	"encoding/yaml"
	"github.com/joker9944/k8s-config/schema"
)

bundle: schema.#Bundle & {
	namespace: "volsync-system"
	needs: ["monitoring"]
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "backube", url: "https://backube.github.io/helm-charts/"},
	]
	releases: [_volsync]
}

_volsync: schema.#Release & {
	name:      "volsync"
	namespace: bundle.namespace
	chart:     "volsync"
	// renovate: datasource=helm packageName=volsync registryUrl=https://backube.github.io/helm-charts/
	version:    "0.17.0"
	sourceName: "backube"
	interval:   "5m"
	hasValues:  false

	// The chart emits a ServiceMonitor carrying no credentials for a metrics
	// endpoint it guards, so the scrape answers 401; `scrapeClass` supplies the
	// token, and kube-prometheus-stack carries why it cannot sit on the endpoint
	// itself. The explicit target is load-bearing, not decoration: the chart
	// renders this object only where the ServiceMonitor CRD already exists, and
	// an inline patch without a target fails the whole render wherever it does
	// not. With the target, the patch no-ops instead.
	postRenderers: [{kustomize: patches: [{
		target: {
			group:   "monitoring.coreos.com"
			version: "v1"
			kind:    "ServiceMonitor"
			// quoted so the label does not bind `name` and shadow the field above
			"name": name
		}
		patch: yaml.Marshal({
			apiVersion: "monitoring.coreos.com/v1"
			kind:       "ServiceMonitor"
			metadata: "name":  name
			spec: scrapeClass: "service-account"
		})
	}]}]
}
