package cnpgconfig

// cSpell:ignore cnpgconfig

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#ConfigBundle & {
	source: "infrastructure/nyx/config/cnpg"
	resources: [_artifacts.out, _sync]
}

let ns = "cnpg"

// Upstream publishes the ClusterImageCatalogs the fleet's Clusters resolve their
// Postgres images through, so they are tracked rather than copied.
_artifacts: schema.#GitRepo & {
	name:   "cnpg-artifacts"
	"ns":   ns
	url:    "https://github.com/cloudnative-pg/artifacts"
	branch: "main"
	ignore: """
		# exclude all
		/*
		# include image catalogs
		!/image-catalogs
		"""
}

_sync: {
	apiVersion: "kustomize.toolkit.fluxcd.io/v1"
	kind:       "Kustomization"
	metadata: {name: "cnpg-image-catalogs", namespace: ns}
	spec: {
		interval: "30m"
		path:     "./image-catalogs"
		prune:    true
		sourceRef: {kind: "GitRepository", name: _artifacts.name}
	}
}
