package tailscaleoperator //cSpell:ignore tailscaleoperator

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "tailscale-operator"
	extraSecretFiles: ["infrastructure/controllers/tailscale-operator/secrets/tailscale-oauth.secret.yaml"]
	wait:        true
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "tailscale", url: "https://pkgs.tailscale.com/helmcharts", interval: "30m"},
	]
	releases: [_tailscaleOperator]
}

_tailscaleOperator: schema.#Release & {
	name:      "tailscale-operator"
	namespace: bundle.namespace
	chart:     "tailscale-operator"
	// renovate: datasource=helm packageName=tailscale-operator registryUrl=https://pkgs.tailscale.com/helmcharts
	version:    "1.104.4"
	sourceName: "tailscale"
	interval:   "5m"
	values: fullnameOverride: "tailscale-operator"
}
