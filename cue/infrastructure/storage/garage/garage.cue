package garage

// cSpell:ignore Deuxfleurs deuxfleurs

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "garage"
	repositories: [_garageRepo]
	releases: [_garage]
}

// The chart lives in the project's own git repository rather than a chart
// registry, so the source is the repository and the chart is a path inside it.
_garageRepo: schema.#GitRepo & {
	name: "garage"
	url:  "https://git.deuxfleurs.fr/Deuxfleurs/garage"
	// renovate: datasource=git-tags packageName=https://git.deuxfleurs.fr/Deuxfleurs/garage
	tag: "v2.4.1"
	ignore: """
		# exclude all
		/*
		# include helm chart
		!/script/helm/
		"""
}

_garage: schema.#Release & {
	name:       "garage"
	namespace:  bundle.namespace
	chart:      "script/helm/garage"
	version:    "" // a git ref, not a chart version
	sourceKind: "GitRepository"
	sourceName: _garageRepo.name
	crds:       true

	host: "s3.vonarx.online"
	let wildcardHost = "*.\(host)"

	values: {
		"garage": s3: {
			api: {region: "nyx", rootDomain: ".s3.vonarx.online"}
			web: rootDomain: ".web.vonarx.online"
		}

		persistence: {
			meta: {storageClass: "longhorn-local-strict", size: "6Gi"}
			data: {storageClass: "longhorn-local-strict", size: "120Gi"}
		}

		// the garage chart keys its ingresses by protocol, not by release name
		ingress: s3: api: {
			enabled:     true
			annotations: _garage.ingressAnnotations
			hosts: [for h in [host, wildcardHost] {
				"host": h
				paths: [{path: "/", pathType: "Prefix"}]
			}]
			tls: [{hosts: [host, wildcardHost], secretName: "wildcard-vonarx-online-cert"}]
		}

		monitoring: metrics: {
			enabled: true
			serviceMonitor: enabled: true
		}
	}
}
