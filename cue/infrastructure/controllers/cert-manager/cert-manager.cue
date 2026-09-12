package certmanager

// cSpell:ignore certmanager jetstack

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "cert-manager"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "jetstack", url: "https://charts.jetstack.io"},
	]
	releases: [_certManager, _trustManager]
}

_certManager: schema.#Release & {
	name:      "cert-manager"
	namespace: bundle.namespace
	chart:     "cert-manager"
	// renovate: datasource=helm packageName=cert-manager registryUrl=https://charts.jetstack.io
	version:    "v1.21.2"
	sourceName: "jetstack"
	crds:       true

	values: "crds": enabled: true
}

// Distributes the private CA bundle into every namespace that asks for it; the
// two Bundles it reconciles come from the certs-config package.
_trustManager: schema.#Release & {
	name:      "trust-manager"
	namespace: bundle.namespace
	chart:     "trust-manager"
	// renovate: datasource=helm packageName=trust-manager registryUrl=https://charts.jetstack.io
	version:    "v0.25.0"
	sourceName: "jetstack"

	values: secretTargets: {
		enabled: true
		authorizedSecrets: ["nyx-ca-cert-bundle", "public-nyx-ca-cert-bundle"]
	}
}
