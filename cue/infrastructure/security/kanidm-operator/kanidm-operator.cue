package kanidmoperator

// cSpell:ignore kanidmoperator kaniop

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "kanidm-system"
	wait:        true
	middlewares: false
	repositories: [_repo]
	releases: [_kaniop]
}

_repo: schema.#HelmRepo & {
	name: "kaniop"
	type: "oci"
	url:  "oci://ghcr.io/pando85/helm-charts"
}

_kaniop: schema.#Release & {
	name:      "kanidm-operator"
	namespace: bundle.namespace
	chart:     "kaniop"
	// renovate: datasource=docker packageName=ghcr.io/pando85/helm-charts/kaniop
	version:    "0.22.1"
	sourceName: _repo.name
	crds:       true
	values: {
		fullnameOverride: "kanidm-operator"
		// Helm's crds/ directory already carries the same CRDs under CreateReplace;
		// the hook Job would apply them a second time with its own cluster RBAC.
		crdApply: enabled: false
	}
}
