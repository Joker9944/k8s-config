package metallb

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "metallb-system"
	source:      "infrastructure/base/metallb"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "metallb", url: "https://metallb.github.io/metallb"},
	]
	namespaceLabels: {
		"pod-security.kubernetes.io/enforce": "privileged"
		"pod-security.kubernetes.io/audit":   "privileged"
		"pod-security.kubernetes.io/warn":    "privileged"
	}
	releases: [_metallb]
}

_metallb: schema.#Release & {
	name:       "metallb"
	namespace:  bundle.namespace
	chart:      "metallb"
	version:    "0.16.1"
	sourceName: "metallb"
	interval:   "5m"
	crds:       true
	hasValues:  false
}
