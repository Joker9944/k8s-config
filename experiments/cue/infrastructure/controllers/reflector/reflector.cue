package reflector

// cSpell:ignore emberstack

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "reflector-system"
	source:      "infrastructure/base/reflector"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "emberstack", url: "https://emberstack.github.io/helm-charts"},
	]
	releases: [_reflector]
}

_reflector: schema.#Release & {
	name:       "reflector"
	namespace:  bundle.namespace
	chart:      "reflector"
	version:    "9.1.45"
	sourceName: "emberstack"
	interval:   "5m"
	crds:       true
	hasValues:  false
}
