package stakater

// cSpell:ignore stakater

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "stakater-system"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "stakater", url: "https://stakater.github.io/stakater-charts"},
	]
	releases: [_reloader]
}

// Rolls a workload when a Secret it names in a reload annotation changes;
// kanidm uses it to pick up its renewed certificate.
_reloader: schema.#Release & {
	name:      "reloader"
	namespace: bundle.namespace
	chart:     "reloader"
	// renovate: datasource=helm packageName=reloader registryUrl=https://stakater.github.io/stakater-charts
	version:    "2.2.17"
	sourceName: "stakater"
	hasValues:  false
}
