package redisoperator

// cSpell:ignore redisoperator

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "redis-operator"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "ot-helm", url: "https://ot-container-kit.github.io/helm-charts", interval: "30m"},
	]
	releases: [_redisOperator]
}

_redisOperator: schema.#Release & {
	name:      "redis-operator"
	namespace: bundle.namespace
	chart:     "redis-operator"
	// renovate: datasource=helm packageName=redis-operator registryUrl=https://ot-container-kit.github.io/helm-charts
	version:    "0.26.1"
	sourceName: "ot-helm"
	interval:   "5m"
	crds:       true

	// the operator ships a cert-manager Issuer of its own; the fleet's certs
	// come from the nyx-intermediate-ca ClusterIssuer instead
	values: issuer: create: false
}
