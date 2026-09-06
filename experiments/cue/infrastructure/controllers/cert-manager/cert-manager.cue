package certmanager

// cSpell:ignore certmanager jetstack

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "cert-manager"
	source:      "infrastructure/base/cert-manager"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "jetstack", url: "https://charts.jetstack.io"},
	]
	releases: [_certManager, _trustManager]
}

_certManager: schema.#Release & {
	name:       "cert-manager"
	namespace:  bundle.namespace
	chart:      "cert-manager"
	version:    "v1.21.0"
	sourceName: "jetstack"
	crds:       true

	values: "crds": enabled: true
}

// Distributes the private CA bundle into every namespace that asks for it; the
// two Bundles it reconciles live in infrastructure/nyx/config/certs.
_trustManager: schema.#Release & {
	name:       "trust-manager"
	namespace:  bundle.namespace
	chart:      "trust-manager"
	version:    "v0.24.0"
	sourceName: "jetstack"

	values: secretTargets: {
		enabled: true
		authorizedSecrets: ["nyx-ca-cert-bundle", "public-nyx-ca-cert-bundle"]
	}
}
