package volsync

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "volsync-system"
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
	version:    "0.16.0"
	sourceName: "backube"
	interval:   "5m"
	crds:       true
	hasValues:  false
}
