@extern(embed)

package alloy

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "alloy"
	dependsOn: ["loki"]
	middlewares: false
	repositories: [_grafana]
	before: [_config.out]
	releases: [_alloy]
}

_grafana: schema.#HelmRepo & {name: "grafana", url: "https://grafana.github.io/helm-charts"}

// Plaintext config, read from disk at evaluation time. @embed cannot escape the
// package directory, which is why this file lives here.
_configAlloy: _ @embed(file="files/config.alloy", type=text)

_config: schema.#ConfigMapFiles & {
	name: "alloy-config"
	ns:   bundle.namespace
	files: "config.alloy": _configAlloy
}

_alloy: schema.#Release & {
	name:      "alloy"
	namespace: bundle.namespace
	chart:     "alloy"
	// renovate: datasource=helm packageName=alloy registryUrl=https://grafana.github.io/helm-charts
	version:    "1.12.1"
	sourceName: _grafana.name

	// The CRDs come with the loki release, which is why this one installs none.
	// The chart is pointed at the ConfigMap above rather than templating its own;
	// upstream asks for exactly this when the config is managed outside the chart.
	values: {
		alloy: {
			configMap: {
				create: false
				name:   _config.name
				key:    "config.alloy"
			}

			// Builds the alloy-cluster headless Service and passes
			// --cluster.enabled. The config's clustering blocks are inert without
			// it, which is what let four replicas ship the same lines.
			clustering: enabled: true
		}
		controller: tolerations: [schema.#Reserved.any]
	}
}
