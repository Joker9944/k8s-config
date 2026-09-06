package cnpg

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "cnpg"
	source:      "infrastructure/base/cnpg"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "cnpg", url: "https://cloudnative-pg.github.io/charts/"},
	]
	releases: [_cnpg, _barman]
}

_cnpg: schema.#Release & {
	name:       "cnpg"
	namespace:  bundle.namespace
	chart:      "cloudnative-pg"
	version:    "0.29.0"
	sourceName: "cnpg"
	interval:   "5m"
	crds:       true
	hasValues:  false
}

// The CNPG-I plugin servarr backs Postgres up through. Its Service, its
// cnpg.io/pluginName label and its two TLS secrets are what the operator
// resolves, and the chart names all three exactly as the raw manifest did.
_barman: schema.#Release & {
	name:       "barman-cloud"
	namespace:  bundle.namespace
	chart:      "plugin-barman-cloud"
	version:    "0.5.0"
	sourceName: "cnpg"
	interval:   "5m"
	crds:       true
	hasValues:  false
}
