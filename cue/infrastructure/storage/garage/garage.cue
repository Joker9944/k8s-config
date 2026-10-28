@extern(embed)

package garage

// cSpell:ignore Deuxfleurs deuxfleurs

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "garage"
	needs: ["monitoring"]
	wait: true
	before: [_logs.out]
	repositories: [_garageRepo]
	releases: [_garage]
}

_garageLogs: _ @embed(file="files/garage.alloy", type=text)

// garage's log pipeline, shipped with the app rather than with alloy.
_logs: schema.#AlloyPipeline & {
	app:    "garage"
	ns:     bundle.namespace
	config: _garageLogs
}

// The chart lives in the project's own git repository rather than a chart
// registry, so the source is the repository and the chart is a path inside it.
_garageRepo: schema.#GitRepo & {
	name: "garage"
	url:  "https://git.deuxfleurs.fr/Deuxfleurs/garage"
	// renovate: datasource=git-tags packageName=https://git.deuxfleurs.fr/Deuxfleurs/garage
	tag: "v2.5.0"
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

	host: "s3.vonarx.online"
	let wildcardHost = "*.\(host)"

	values: {
		// The chart has no pod-specific label value; commonLabels is what reaches
		// the pod template. garage.selectorLabels is a separate helper, so the
		// StatefulSet's immutable selector is untouched.
		commonLabels: _logs.podLabels

		// Logging is configured at the app rather than parsed in alloy: the JSON
		// mode removes the format regex, and the two level directives keep the
		// steady-state resync and gc chatter — 84% of this workload's volume —
		// from ever being emitted. Setting RUST_LOG replaces garage's own default
		// (main.rs:193-199), so the stock pair has to be restated.
		environment: [
			{name: "GARAGE_LOG_FORMAT", value: "json"},
			{name: "RUST_LOG", value: "netapp=info,garage=info,garage_block::resync=warn,garage_table::gc=warn"},
		]

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
